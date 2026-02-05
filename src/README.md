# Dev Notes
This note serves as a doc to help co-developers understand the code structure and logic. 
**Devs are encouraged to document any important design decisions or implementation details here.**
## Reference
Our implementation is based on:
1. [ASP-DAC24-Tutorial/blob/main/session1/demo2_gate_sizing_helpers.py](https://github.com/ASU-VDA-Lab/ASP-DAC24-Tutorial/blob/main/session1/demo2_gate_sizing_helpers.py) 
2. [ASP-DAC24-Tutorial/blob/main/session1/demo2_gate_sizing.py](https://github.com/ASU-VDA-Lab/ASP-DAC24-Tutorial/blob/main/session1/demo2_gate_sizing.py) 

Key differences from ASP-DAC24-Tutorial:
1. We consider multiple VTs; the reference does not.
2. Their goal is to minimize clock period, while we optimize multiple metrics under fixed timing and additional constraints.

As a result, we modified the gate sizing algorithm, data structures, and added more constraints and objectives.

## Code Structure
### Key data structures
1. `inst_dict`: A dictionary mapping instance names to their properties, including index, cell type, size index, slack, slew, load, area.
```python
inst_dict[inst_name] = {
          'idx':len(inst_dict),
          'cell_type_name':cell_type,
          # This is a tuple (cell_idx, size_idx)
          'cell_type':get_type(cell_type, cell_dict, cell_name_dict),
          'slack':0,
          'slew':0,
          'load':0,
          'cin':0,
          'area': area,
          # VT attr to be added later
          }
```
2. `cell_dict`: A dictionary mapping cell indices to their properties, including number of sizes, area for each size, delay for each size, and power for each size.
```python
cell_dict[cell_idx] = {
          'n_sizes': n_sizes,
          'areas': areas,  # list of areas for each size
          'delays': delays,  # list of delays for each size
          'powers': powers,  # list of powers for each size
          }
```
3. `cell_name_dict`: A dictionary mapping base cell names (without size and VT) to their indices in `cell_dict`.
```python
cell_name_dict[base_cell_name] = cell_idx
```
