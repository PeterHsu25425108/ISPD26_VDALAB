```
The value of TNS updated seems comparable with tns max, but in latter episodes it seems TNS updated cannot reflect tns max's trend. Help me identify the possible cause of this issue.
```

I’ll trace exactly where `tns max` and `TNS updated` are computed and logged, then pinpoint why their trends diverge across episodes.

Searched for regex `max_TNS|max_WNS|TNS updated|tns max|run_gr\(` (`**/src/demo2_gate_sizing.py`), 9 results

Searched for regex `def run_gr\(|report_tns|estimate_parasitics|global_route` (`**/src/demo2_gate_sizing_helpers.py`), 15 results

Read [](file:///workspace/ISPD26_VDALAB/src/demo2_gate_sizing_helpers.py#1199-1199), lines 1199 to 1221

Yes — your log already shows a strong clue, and there are 4 likely causes.

- In demo2_gate_sizing.py, TNS updated prints max_TNS, where max_TNS only updates when new_TNS > max_TNS. Since TNS is negative, this keeps the best (least-negative) historical value, so it cannot track worsening trends later.
- max_TNS is global (initialized once) and not reset per episode in demo2_gate_sizing_helpers.py, so each episode compares against prior episodes’ best TNS.
- TNS updated is computed before global routing (inside RL loop), while tns max is printed after run_gr/report_tns. You are comparing different timing states: placement parasitics vs global-routing parasitics. See demo2_gate_sizing.py and demo2_gate_sizing_helpers.py.
- episode_TNS also uses max(episode_TNS, new_TNS) in demo2_gate_sizing.py, which further smooths/hides trend changes.

If you want trend alignment, print current new_TNS (or reset max_TNS each episode), and compare it to report_tns taken at the same stage (either both pre-GR or both post-GR). Want me to patch this so logs show per-episode current/best TNS separately?

I’ll apply the patch now to make logs report both **current** and **best-this-episode** TNS/WNS, and stop using a cross-episode best that masks trends.

Read [](file:///workspace/ISPD26_VDALAB/src/demo2_gate_sizing.py#240-240), lines 240 to 430

Generating patch (69 lines) in [](file:///workspace/ISPD26_VDALAB/src/demo2_gate_sizing.py)


```
Yes
```
I’ve patched the logging logic to show per-episode **current** and **best** TNS/WNS, which removes the trend masking from global best tracking. I’ll quickly sanity-check for leftover references to the old `max_TNS/max_WNS` usage in this file.

Searched for regex `max_TNS|max_WNS|WNS updated|TNS updated|WNS current|TNS current` (`**/src/demo2_gate_sizing.py`), 2 results

Great, this is now fixed for trend visibility.

- I updated logging in demo2_gate_sizing.py so each episode reports:
  - `WNS current (ns)`
  - `TNS current (ns)`
  - `WNS best in episode (ns)`
  - `TNS best in episode (ns)`
- I removed the use of cross-episode `max_WNS/max_TNS` for these prints, which was the main reason trends looked “stuck” or inconsistent with `tns max`.
- `TNS current` is still endpoint-based (same definition you aligned earlier), so it remains comparable in unit and meaning.

If you run `bash dev_run.sh aes_cipher_top` again, your runtime log should now show per-episode trend changes directly.

Made changes.