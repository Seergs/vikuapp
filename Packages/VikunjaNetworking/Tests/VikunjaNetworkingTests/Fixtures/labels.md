# Label fixture

`labels.json` is a real `GET /api/v1/labels?page=1&per_page=3` response
captured from Vikunja 2.8.0 on 2026-11-13. Creator identity is anonymized,
and the Spanish label title is translated to English.

Label download tests derive page boundaries and v2 envelopes from these records,
changing IDs when expanding to more than fifty labels. This exercises the actual
label payload and mapping while allowing deterministic page sizes and failures.
