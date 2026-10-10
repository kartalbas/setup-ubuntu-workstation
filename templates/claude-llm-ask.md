## Your own LLM servers: llm-ask

`llm-ask NAME "QUESTION" [FILE|-]` puts one question to one of this account's own LLM servers, with a text file, an image or standard input after it; `llm-ask --list` names the servers. It uses no account quota.
- A helper only: summing up a log, reading a screenshot, a second reader of a diff. Never the deciding review, never code that lands, never a decision.
- Give it the part that matters, such as the failing part of a log, not a whole tree: a small model loses the thread in a long input.
- A server answers one request at a time; the others wait in its queue.
- Exit 1 with "gave no answer": ask again, or with less input.
