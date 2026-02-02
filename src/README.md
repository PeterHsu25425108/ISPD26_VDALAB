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