# Emotional salience contract

## Labels

Use zero or more non-neutral labels. Use `neutral` only when no other label applies.

- `neutral`: no observable affective or corrective signal
- `confusion`: asks for clarification or signals a broken mental model
- `correction`: says the current understanding or behavior is wrong
- `frustration`: expresses dissatisfaction with process or result
- `urgency`: requests faster or immediate action
- `approval`: explicitly accepts or positively reinforces a result
- `boundary_assertion`: states what must or must not happen
- `preference_assertion`: states a preferred way of working or designing
- `concern`: flags risk or unease without direct rejection

## Scales

- `intensity`: 0–3 observable expression strength. Do not use project importance to inflate it.
- `memory_salience`: 0–3 likelihood that the semantic target should affect future project behavior. Do not use punctuation alone to inflate it.

## Actions

- `ignore`: transient and not useful beyond the immediate exchange
- `retain_signal`: useful short-term attention signal, not yet durable knowledge
- `propose_boundary`: candidate project rule or prohibition
- `propose_preference`: candidate durable design/process preference
- `record_conflict`: unresolved contradiction, ambiguity, or consistency problem

## Decision discipline

- Use the smallest label set directly supported by the wording. Do not add a
  preference label merely because an accepted convention could become durable.
- A calm architectural rule, role limit, compatibility requirement, or explicit
  prohibition can have low intensity and high memory salience.
- `neutral` describes observable affect, not knowledge value. A neutral verified
  finding or technical constraint may still have high memory salience when it changes
  future project decisions.
- Set `durable_candidate` to true exactly when `memory_salience >= 2`; otherwise set
  it to false. This field is derived, not an independent intuition.
- A bare speed request is `ignore`. Frustration about a process failure may be
  `retain_signal`, even when it is not durable knowledge.
- A correction that redirects future scope or agent behavior is a durable boundary;
  a one-off concrete correction, including aesthetic feedback, is normally
  `retain_signal` rather than durable knowledge.
- A contradiction between prior and current claims is `record_conflict`; preserve
  the disputed topic without deciding which claim is true.
- Capitalization, repeated punctuation, or words such as MUST and DO NOT can raise
  observable intensity, but never raise memory salience by themselves.
- Never infer a hidden emotion, personality, motive, diagnosis, or stable trait.

Choose `recommended_action` in this order:

1. Use `record_conflict` for unresolved contradictions or explicitly deferred
   ambiguities, regardless of whether the conflict is durable. A general principle
   about how contradictions should be handled is not itself a current conflict.
2. If durable, use `propose_boundary` for must/must-not rules, role or scope limits,
   storage/location architecture, compatibility constraints, and corrections that
   redirect future behavior.
3. If durable, use `propose_preference` for a preferred tool, style, convention, or
   design/process direction that is not a hard limit.
4. If not durable, use `retain_signal` only for a concrete correction or frustration
   that should influence the immediate work.
5. Otherwise use `ignore`, including pure urgency, acknowledgements, routine facts,
   temporary deferrals, and neutral task narration.

Additional disambiguation:

- A deadline or one-task instruction remains pure urgency even if it contains words
  such as "must"; it is durable only when it establishes a future recurring rule.
- A debugging question that merely asks why an operation failed is `ignore` after
  labeling confusion. Do not retain confusion without an unresolved project-level
  ambiguity.
- A direct complaint that the process or execution is failing or taking too long is
  `retain_signal`; a bare status check or request to hurry is `ignore`.
- An explicit storage/location requirement is a boundary. A request to discuss before
  implementing is normally a process preference unless phrased as a recurring ban.

## Output

```json
{
  "schema_version": 1,
  "predictions": [
    {
      "id": "sample-001",
      "labels": ["correction", "boundary_assertion"],
      "intensity": 2,
      "memory_salience": 3,
      "durable_candidate": true,
      "target_topic": "short topic",
      "recommended_action": "propose_boundary",
      "rationale": "One sentence grounded only in the supplied text."
    }
  ]
}
```
