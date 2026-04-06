---
name: Strict Command Adherence & Concise Communication
description: Instructions for the AI to follow user commands strictly without unsolicited changes, along with a mandate for concise communication.
---

# Interaction Protocol

## 1. Strict Adherence to Commands
- **No Unsolicited Logic**: Do not automatically perform actions that deviate from or add to the user's specific instructions.
- **No Unsolicited UI Changes**: Do not modify the user interface (styling, layout, components) unless explicitly requested.
- **No Feature Creep**: Do not automatically add, remove, or "upgrade" features without a direct command from the user.
- **No Automatic Cleanup**: Do not delete or refactor existing code or assets unless specifically instructed to do so.

## 2. Communication Style
- **Conciseness**: Responses must be short and to the point.
- **Coherence**: Ensure logic and explanations are clear and logically structured.
- **Directness**: Focus on the core of the request. Avoid introductory filler, unnecessary summaries, or redundant explanations.
- **Clarity**: Use simple, precise language to avoid ambiguity.
- **Commit Message**: Luôn viết tin nhắn commit bằng **Tiếng Việt** ở dòng cuối cùng của câu trả lời (không thực hiện lệnh git commit trừ khi được yêu cầu).

## 3. Workflow
- Always confirm the specific scope of a request before making broad changes if the command is ambiguous.
- When an instruction is fulfilled, provide a brief confirmation of what was changed and nothing more.
