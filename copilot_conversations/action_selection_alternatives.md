User: I want to use the new_TNS value using the slacks of the entire updated timing graph, is it possible?

GitHub Copilot: Let me look at the `env_step` function in detail to understand how `new_TNS` is currently computed. 

Read [](file:///workspace/ISPD26_VDALAB/src/demo2_gate_sizing_helpers.py#380-380), lines 380 to 515

Now I can see the full picture. Currently `new_TNS` is computed from `new_slacks` (per-node raw slacks) with per-node `Slack_Lambda` weighting and a normalization `factor`. The user wants to use the scalar TNS directly from `episode_G.ndata['slack']` (the full updated timing graph).

Here's the change — replace the per-node weighted TNS reward with a scalar delta-TNS from the full graph: 

Replacing 10 lines with 9 lines in [](file:///workspace/ISPD26_VDALAB/src/demo2_gate_sizing_helpers.py)


```

```
Let me verify the result: 

Read [](file:///workspace/ISPD26_VDALAB/src/demo2_gate_sizing_helpers.py#492-492), lines 492 to 515

Done. Here's what changed and why it's correct:

**Before:** `new_TNS` was computed per-node from `new_slacks`, then weighted by `Slack_Lambda` and a per-node normalization `factor`, producing a hard-to-interpret scaled reward.

**After:** 
- `new_TNS` = scalar global TNS from `episode_G.ndata['slack']` (the full updated timing graph), de-normalized back to raw units via `* norm_data['clk_period']`
- `old_TNS` = scalar global TNS from `old_slacks` (same raw units)
- Reward contribution = `new_TNS - old_TNS` — a positive value when TNS improves (becomes less negative)

`episode_G.ndata['slack']` is the right source because it's already been fully updated for all nodes after the `estimate_parasitics` call, including propagated timing effects beyond just the resized cell's immediate output pin. The `Slack_Lambda` weighting and `factor` normalization are no longer needed since the scalar TNS difference is already well-scaled in time units.

Made changes.

User: I think the action selection strategy here is too greedy, it only chosses the one with the greastet resulting reward. Recommend me some works that proposes alternatives for RL discrete gate sizing

GitHub Copilot: Here are targeted recommendations, organized by the type of alternative they propose:

---

### 1. Stochastic Policy Gradient (instead of greedy Q-value argmax)

**"DRiLLS: Deep Reinforcement Learning for Logic Synthesis"** (Hosny et al., ICCAD 2020)
Uses A3C with a stochastic policy — the agent samples from a learned probability distribution over actions rather than taking the argmax. Directly applicable to discrete EDA optimization.

**"PRIMAL: Pathfinding via Reinforcement and Imitation Multi-Agent Learning"** — demonstrates that stochastic policies via PPO outperform epsilon-greedy DQN in constrained discrete action spaces, avoiding myopic exploitation.

---

### 2. Soft Actor-Critic for Discrete Actions (entropy-regularized)

**"Soft Actor-Critic for Discrete Action Settings"** (Christodoulou, arXiv 2019)
Extends SAC to discrete spaces. Maximizes a trade-off between reward and policy entropy, which directly counters the greediness — the agent is *penalized* for being too confident, encouraging broader exploration of sizing choices.

---

### 3. Distributional RL (model uncertainty over returns)

**"A Distributional Perspective on Reinforcement Learning"** (Bellemare et al., ICML 2017 — C51)
Instead of predicting a single Q-value, model the full return distribution. For gate sizing, this is useful because the same sizing action can have high variance in timing improvement (depends on fanout, path criticality). Action selection uses the distribution rather than expected value, reducing overcommitment to locally greedy choices.

---

### 4. MCTS / Lookahead Search with Neural Guidance

**"AlphaSyn: Logic Synthesis Optimization with a Learning-Based Approach"** (Shi et al., ICCAD 2023)
Applies AlphaZero-style MCTS to discrete synthesis. Rather than a single-step greedy pick, MCTS rolls out multiple candidate action sequences and backpropagates value estimates — directly addressing short-sightedness of argmax.

---

### 5. Multi-Objective / Constrained RL

**"MFRL: A Multi-Fidelity Reinforcement Learning Framework for Timing Optimization"** and more generally **"Constrained Policy Optimization (CPO)"** (Achiam et al., ICML 2017) — treats area as a constraint rather than part of the reward, so the policy explores timing improvements without greedily trading against area at each step.

---

### Key Takeaway for Your Code

The current `select_action` uses $\epsilon$-greedy with hard argmax, meaning once $\epsilon \to 0$, every action is deterministically the highest Q-value cell. The most impactful drop-in alternative would be **SAC-Discrete** or **PPO with a softmax policy head** — both replace the `argmax` with a temperature-scaled sample, which in gate sizing context means occasionally accepting a suboptimal local step to escape saddle points in the TNS/area trade-off surface.