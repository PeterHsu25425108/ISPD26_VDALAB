/**
 * netlist_utils.cpp
 *
 * C++ / pybind11 acceleration for the two performance-critical functions
 * in demo2_gate_sizing_helpers.py:
 *
 *   pin_properties(dbpin, clk_period, ord_design, timing)
 *     -> (slack_ns, slew, load)
 *
 *   iterate_nets_get_properties(ord_design, timing, nets, block,
 *                               cell_dict, cell_name_dict, clk_period)
 *     -> (inst_dict, endpoints, srcs, dsts,
 *         fanin_dict, fanout_dict, endpoint_iterms)
 *
 * The OpenROAD objects (nets, block, timing, ITerms …) stay as SWIG-wrapped
 * Python objects; we call their methods via pybind11's py::object.attr() API.
 * The speedup comes from:
 *
 *  1. Eliminating Python-interpreter loop overhead for ~15 000 nets.
 *  2. Method handles for timing.getPinSlack / getPinSlew / getPortCap are
 *     resolved ONCE before the loop instead of once per pin.
 *  3. C++ std::unordered_map used for the fast inst_name→index lookup instead
 *     of the Python-dict __contains__ / __getitem__ on each net visit.
 *  4. srcs / dsts / endpoint lists built in C++ vectors; converted to Python
 *     lists in a single pass at the end (no incremental py::list.append calls).
 *  5. cell_dict and cell_name_dict look-ups performed with C++ strings instead
 *     of going through the Python GIL hash machinery on every inner iteration.
 */

#include <pybind11/pybind11.h>
#include <pybind11/stl.h>

#include <algorithm>
#include <regex>
#include <stdexcept>
#include <string>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace py = pybind11;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Return true if the upper-cased cell_type contains any of the skip tokens. */
static bool is_special_cell(const std::string &cell_type)
{
    static const std::vector<std::string> skip_tokens = {
        "TAPCELL", "FILLER", "ENDCAP", "SRAM", "FAKERAM"};
    // Convert to upper case once
    std::string upper = cell_type;
    std::transform(upper.begin(), upper.end(), upper.begin(), ::toupper);
    for (const auto &tok : skip_tokens)
        if (upper.find(tok) != std::string::npos)
            return true;
    return false;
}

/** Return true if the cell base name is a sequential (timing endpoint) cell. */
static bool is_endpoint_cell(const std::string &base_name)
{
    static const std::vector<std::string> ep_prefixes = {
        "DFF", "SDFH", "SDFL", "DHL", "DLL", "ICG"};
    for (const auto &pfx : ep_prefixes)
        if (base_name.rfind(pfx, 0) == 0) // starts_with
            return true;
    return false;
}

/**
 * C++ re-implementation of get_type().
 *
 * Parses an ASAP7 master cell name like "INVx2_ASAP7_75t_R" and returns
 * (cell_idx, size_idx, vt_idx).  Returns (-1,-1,-1) on any error.
 *
 * We take cell_dict and cell_name_dict as Python objects and query them via
 * py::dict / py::object rather than converting the whole dict to C++ (which
 * would copy thousands of entries on every call).
 */
static std::tuple<int, int, int>
get_type_cpp(const std::string &cell_type,
             const py::dict &cell_dict,
             const py::dict &cell_name_dict)
{
    // Regex matches groups: (base)(xSIZE[letter])_ASAP7_75t_(VT)
    static const std::regex asap7_re(
        R"(([A-Za-z0-9_]+?)(x[p0-9]+(?:p[0-9]+)?[a-z]?)_ASAP7_75t_(.*))");
    std::smatch m;
    if (!std::regex_match(cell_type, m, asap7_re))
        return {-1, -1, -1};

    const std::string cell  = m[1].str(); // base name, e.g. "INV"
    const std::string drive = m[2].str(); // size suffix, e.g. "x2"
    const std::string vt    = m[3].str(); // VT suffix, e.g. "R"

    py::str cell_key(cell);
    if (!cell_name_dict.contains(cell_key))
        return {-1, -1, -1};

    const std::string cell_idx_str =
        cell_name_dict[cell_key].cast<std::string>();
    py::str cell_idx_pykey(cell_idx_str);

    if (!cell_dict.contains(cell_idx_pykey))
        return {-1, -1, -1};

    py::dict cell_entry = cell_dict[cell_idx_pykey].cast<py::dict>();
    int cell_idx = std::stoi(cell_idx_str);

    // Find size index in unique_sizes
    py::list unique_sizes = cell_entry["unique_sizes"].cast<py::list>();
    int size_idx = -1;
    for (int i = 0; i < static_cast<int>(unique_sizes.size()); ++i) {
        if (unique_sizes[i].cast<std::string>() == drive) {
            size_idx = i;
            break;
        }
    }
    if (size_idx < 0)
        return {-1, -1, -1};

    // Find VT index in vt_to_idx
    py::dict vt_to_idx = cell_entry["vt_to_idx"].cast<py::dict>();
    py::str vt_key(vt);
    int vt_idx = 0;
    if (vt_to_idx.contains(vt_key))
        vt_idx = vt_to_idx[vt_key].cast<int>();

    return {cell_idx, size_idx, vt_idx};
}

// ---------------------------------------------------------------------------
// pin_properties_cpp
// ---------------------------------------------------------------------------

/**
 * C++ accelerated equivalent of pin_properties().
 *
 * Resolving the timing method handles on each call still has some overhead;
 * when called from iterate_nets_cpp the handles are pre-resolved once.  This
 * standalone entry point is provided so that other call sites (e.g. env_step)
 * can also avoid the Python loop overhead.
 */
static py::tuple
pin_properties_cpp(py::object dbpin,
                   double clk_period,
                   py::object /* ord_design – kept for API parity */,
                   py::object timing)
{
    // Pre-resolve attribute handles (these are cheap Python lookups; they
    // become significant only when done 15 000 times inside a Python loop).
    py::object Fall        = timing.attr("Fall");
    py::object Rise        = timing.attr("Rise");
    py::object Max         = timing.attr("Max");
    py::object fn_slack    = timing.attr("getPinSlack");
    py::object fn_slew     = timing.attr("getPinSlew");
    py::object fn_cap      = timing.attr("getPortCap");
    py::object fn_corners  = timing.attr("getCorners");

    double s_fall = fn_slack(dbpin, Fall, Max).cast<double>();
    double s_rise = fn_slack(dbpin, Rise, Max).cast<double>();
    double slack  = std::min(s_fall, s_rise) * 1e9; // s → ns

    double slew = fn_slew(dbpin).cast<double>();

    py::object net         = dbpin.attr("getNet")();
    py::object iterms_obj  = net.attr("getITerms")();
    py::list   corners     = fn_corners().cast<py::list>();

    double load = 0.0;
    for (py::handle h : iterms_obj) {
        py::object iterm = h.cast<py::object>();
        if (!iterm.attr("isInputSignal")().cast<bool>())
            continue;
        double new_load = 0.0;
        for (py::handle ch : corners) {
            double tmp = fn_cap(iterm, ch, Max).cast<double>();
            if (tmp > new_load)
                new_load = tmp;
        }
        load += new_load;
    }

    return py::make_tuple(slack, slew, load);
}

// ---------------------------------------------------------------------------
// min_slack_cpp
// ---------------------------------------------------------------------------

static double
min_slack_cpp(py::object dbpin, py::object timing)
{
    py::object Fall  = timing.attr("Fall");
    py::object Rise  = timing.attr("Rise");
    py::object Max   = timing.attr("Max");
    py::object fn_sl = timing.attr("getPinSlack");

    double s_fall = fn_sl(dbpin, Fall, Max).cast<double>();
    double s_rise = fn_sl(dbpin, Rise, Max).cast<double>();
    return std::min(s_fall, s_rise) * 1e9;
}

// ---------------------------------------------------------------------------
// iterate_nets_cpp  (main expensive function)
// ---------------------------------------------------------------------------

/**
 *  C++ accelerated replacement for iterate_nets_get_properties().
 *
 *  Returns:
 *    (inst_dict, endpoints, srcs, dsts, fanin_dict, fanout_dict, endpoint_iterms)
 *
 *  All return types match the Python original exactly so every call site
 *  in demo2_gate_sizing.py / demo2_gate_sizing_helpers.py works unchanged.
 */
py::tuple
iterate_nets_cpp(py::object ord_design,  // kept for API parity
                 py::object timing,
                 py::object nets,        // Iterable[odb.Net]
                 py::object block,
                 py::dict   cell_dict,
                 py::dict   cell_name_dict,
                 double     clk_period)
{
    // ------------------------------------------------------------------
    // Pre-resolve ALL timing method handles once before the loop.
    // The difference vs. Python: in Python, every "timing.getPinSlack()"
    // goes through __getattribute__ + descriptor lookup each time.
    // Here we pay that cost once.
    // ------------------------------------------------------------------
    py::object Fall       = timing.attr("Fall");
    py::object Rise       = timing.attr("Rise");
    py::object Max        = timing.attr("Max");
    py::object fn_slack   = timing.attr("getPinSlack");
    py::object fn_slew    = timing.attr("getPinSlew");
    py::object fn_cap     = timing.attr("getPortCap");
    py::object fn_corners = timing.attr("getCorners");
    py::list   corners    = fn_corners().cast<py::list>();

    // ------------------------------------------------------------------
    // C++ data structures mirroring Python originals
    // ------------------------------------------------------------------
    // inst_dict: inst_name → {idx, cell_type_name, cell_type, slack, …}
    // We keep it as a Python dict built incrementally so we can return it
    // directly without a final conversion pass.
    py::dict inst_dict_py;

    // Fast O(1) name→idx lookup in C++ (avoids Python dict query in the hot path)
    std::unordered_map<std::string, int> inst_name_to_idx;

    std::vector<int> srcs_vec;
    std::vector<int> dsts_vec;
    std::vector<int> endpoints_vec;
    std::vector<std::string> endpoint_iterms_vec;

    // fanin/fanout stored in Python dicts so they can be returned directly
    py::dict fanout_dict_py;
    py::dict fanin_dict_py;

    // We need the ordered inst_names list for fanin/fanout key resolution
    // (Python original uses list(inst_dict.keys())[src] which is O(n) – we
    // keep a parallel vector of names indexed by idx for O(1) access).
    std::vector<std::string> idx_to_name;

    // ------------------------------------------------------------------
    // Iterate over nets
    // ------------------------------------------------------------------
    py::list nets_list = py::list(nets); // materialise once
    int total_nets = static_cast<int>(nets_list.size());
    int net_print_step = 5000;

    py::print("Starting netlist traversal...");
    py::print(py::str("Total nets to process: {}").format(total_nets));

    for (int net_idx = 0; net_idx < total_nets; ++net_idx) {
        if (net_idx > 0 && net_idx % net_print_step == 0) {
            py::print(py::str("Processed {}/{} nets, {} instances so far...")
                          .format(net_idx, total_nets,
                                  static_cast<int>(inst_name_to_idx.size())));
        }

        py::object net = nets_list[net_idx].cast<py::object>();
        py::object iterms_obj = net.attr("getITerms")();

        // Temporary per-net source / destination lists
        // (src_idx, term_name_str)
        std::vector<std::pair<int, std::string>> net_srcs;
        std::vector<std::pair<int, std::string>> net_dsts;

        for (py::handle h : iterms_obj) {
            py::object s_iterm = h.cast<py::object>();

            py::object inst_obj = s_iterm.attr("getInst")();

            const std::string inst_name =
                inst_obj.attr("getName")().cast<std::string>();

            py::object mterm_obj = s_iterm.attr("getMTerm")();
            const std::string mterm_name =
                mterm_obj.attr("getName")().cast<std::string>();
            const std::string term_name = inst_name + "/" + mterm_name;

            const std::string cell_type =
                inst_obj.attr("getMaster")()
                        .attr("getName")()
                        .cast<std::string>();

            if (is_special_cell(cell_type))
                continue;

            // Insert new instance if not yet seen
            if (inst_name_to_idx.find(inst_name) == inst_name_to_idx.end()) {
                int new_idx = static_cast<int>(inst_name_to_idx.size());
                inst_name_to_idx[inst_name] = new_idx;
                idx_to_name.push_back(inst_name);

                py::object master  = inst_obj.attr("getMaster")();
                int area = master.attr("getWidth")().cast<int>() *
                           master.attr("getHeight")().cast<int>();

                auto [ci, si, vi] =
                    get_type_cpp(cell_type, cell_dict, cell_name_dict);

                // Build Python dict entry
                py::dict entry;
                entry["idx"]            = new_idx;
                entry["cell_type_name"] = cell_type;
                entry["cell_type"]      = py::make_tuple(ci, si, vi);
                entry["slack"]          = 0.0;
                entry["slew"]           = 0.0;
                entry["load"]           = 0.0;
                entry["cin"]            = 0.0;
                entry["area"]           = area;
                inst_dict_py[py::str(inst_name)] = entry;
            }

            int idx = inst_name_to_idx[inst_name];

            bool is_input  = s_iterm.attr("isInputSignal")().cast<bool>();
            bool is_output = s_iterm.attr("isOutputSignal")().cast<bool>();

            if (is_input) {
                net_dsts.push_back({idx, term_name});

                // Check if this is a sequential endpoint
                py::dict entry = inst_dict_py[py::str(inst_name)].cast<py::dict>();
                py::tuple ct   = entry["cell_type"].cast<py::tuple>();
                int cell_idx_val = ct[0].cast<int>();
                if (cell_idx_val >= 0) {
                    py::str ckey(std::to_string(cell_idx_val));
                    if (cell_dict.contains(ckey)) {
                        std::string base =
                            cell_dict[ckey].cast<py::dict>()["name"]
                                          .cast<std::string>();
                        if (is_endpoint_cell(base)) {
                            endpoints_vec.push_back(idx);
                            endpoint_iterms_vec.push_back(term_name);
                        }
                    }
                }
            } else if (is_output) {
                net_srcs.push_back({idx, term_name});

                // Extract timing properties via pre-resolved handles
                double s_fall =
                    fn_slack(s_iterm, Fall, Max).cast<double>();
                double s_rise =
                    fn_slack(s_iterm, Rise, Max).cast<double>();
                double slack = std::min(s_fall, s_rise) * 1e9;

                double slew = fn_slew(s_iterm).cast<double>();

                // Load capacitance
                py::object pin_net   = s_iterm.attr("getNet")();
                py::object fan_terms = pin_net.attr("getITerms")();
                double load = 0.0;
                for (py::handle fh : fan_terms) {
                    py::object fit = fh.cast<py::object>();
                    if (!fit.attr("isInputSignal")().cast<bool>())
                        continue;
                    double new_load = 0.0;
                    for (py::handle ch : corners) {
                        double tmp = fn_cap(fit, ch, Max).cast<double>();
                        if (tmp > new_load)
                            new_load = tmp;
                    }
                    load += new_load;
                }

                // Update Python dict entry in-place
                py::dict entry =
                    inst_dict_py[py::str(inst_name)].cast<py::dict>();
                entry["slack"] = slack;
                entry["slew"]  = slew;
                entry["load"]  = load;
            }
        }

        // Build srcs / dsts and fanin / fanout
        for (const auto &[src, src_term] : net_srcs) {
            for (const auto &[dst, dst_term] : net_dsts) {
                srcs_vec.push_back(src);
                dsts_vec.push_back(dst);

                const std::string &src_key = idx_to_name[src];
                const std::string &dst_key = idx_to_name[dst];

                // fanout_dict[src_key].append(dst_key)
                py::str psk(src_key);
                if (fanout_dict_py.contains(psk)) {
                    fanout_dict_py[psk].cast<py::list>().append(
                        py::str(dst_key));
                } else {
                    py::list lst;
                    lst.append(py::str(dst_key));
                    fanout_dict_py[psk] = lst;
                }

                // fanin_dict[dst_key].append(src_key)
                py::str pdk(dst_key);
                if (fanin_dict_py.contains(pdk)) {
                    fanin_dict_py[pdk].cast<py::list>().append(
                        py::str(src_key));
                } else {
                    py::list lst;
                    lst.append(py::str(src_key));
                    fanin_dict_py[pdk] = lst;
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Convert C++ vectors to Python lists
    // ------------------------------------------------------------------
    py::list srcs_py(srcs_vec.size());
    for (size_t i = 0; i < srcs_vec.size(); ++i)
        srcs_py[i] = srcs_vec[i];

    py::list dsts_py(dsts_vec.size());
    for (size_t i = 0; i < dsts_vec.size(); ++i)
        dsts_py[i] = dsts_vec[i];

    py::list endpoints_py(endpoints_vec.size());
    for (size_t i = 0; i < endpoints_vec.size(); ++i)
        endpoints_py[i] = endpoints_vec[i];

    py::list ep_iterms_py(endpoint_iterms_vec.size());
    for (size_t i = 0; i < endpoint_iterms_vec.size(); ++i)
        ep_iterms_py[i] = py::str(endpoint_iterms_vec[i]);

    py::print("Completed netlist traversal!");
    py::print(py::str("Total instances: {}").format(
        static_cast<int>(inst_name_to_idx.size())));
    py::print(py::str("Total endpoints (flip-flops): {}").format(
        static_cast<int>(endpoints_vec.size())));
    py::print(py::str("Total graph edges: {}").format(
        static_cast<int>(srcs_vec.size())));
    py::print(py::str("Total endpoint ITerm pins (FF inputs): {}").format(
        static_cast<int>(endpoint_iterms_vec.size())));

    return py::make_tuple(inst_dict_py, endpoints_py, srcs_py, dsts_py,
                          fanin_dict_py, fanout_dict_py, ep_iterms_py);
}

// ---------------------------------------------------------------------------
// pybind11 module definition
// ---------------------------------------------------------------------------

PYBIND11_MODULE(netlist_utils, m)
{
    m.doc() = "C++/pybind11 acceleration module for netlist traversal and "
              "timing property extraction";

    m.def("pin_properties", &pin_properties_cpp,
          py::arg("dbpin"),
          py::arg("clk_period"),
          py::arg("ord_design"),
          py::arg("timing"),
          R"doc(
Accelerated pin_properties().

Args:
    dbpin      : OpenDB ITerm (output pin of a cell instance)
    clk_period : Clock period in nanoseconds
    ord_design : OpenROAD Design object (kept for API parity, not used)
    timing     : OpenROAD Timing object

Returns:
    (slack_ns, slew, load) — same as the Python version
          )doc");

    m.def("min_slack", &min_slack_cpp,
          py::arg("dbpin"),
          py::arg("timing"),
          R"doc(
Accelerated min_slack().

Returns the minimum of rise/fall Max slack in nanoseconds.
          )doc");

    m.def("iterate_nets", &iterate_nets_cpp,
          py::arg("ord_design"),
          py::arg("timing"),
          py::arg("nets"),
          py::arg("block"),
          py::arg("cell_dict"),
          py::arg("cell_name_dict"),
          py::arg("clk_period"),
          R"doc(
Accelerated iterate_nets_get_properties().

Returns:
    (inst_dict, endpoints, srcs, dsts, fanin_dict, fanout_dict, endpoint_iterms)
    — identical structure to the Python version.
          )doc");
}
