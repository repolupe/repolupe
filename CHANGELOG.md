## 1.3.0 (2026-11-13)

- feat: the model can look at images in repositories and attachments (PNG, JPEG, GIF, WebP)
- feat: the model can show images to the user, and images it proposes to save are previewed
- feat: models are asked for high reasoning effort
- feat(app): attach a photo taken with the camera
- feat(app): answers that used no tools say so
- fix: the description of a tool call stays until the answer continues

## 1.2.0 (2026-11-11)

- feat: edit a sent message or retry it, which answers it again and removes the messages after it
- feat: the duration of an answer opens the time spent on the language model and on each tool, with the output speed
- feat: show the raw answer with the system prompt, tools and messages sent to the model
- feat: the token usage shows the cost and the price of each token type
- feat: answers keep the model name, even if the model is changed or deleted later
- feat(web): new user message color
- feat(web): theme mode setting in demo mode
- fix(app): tables too wide to fit scroll instead of being cut off

## 1.1.2 (2026-11-07)

- feat: search older chats
- feat(app): MCP servers can be added, changed, shared and signed in to in the app
- feat(app): rename and delete chats from the chat page menu
- feat(app): "This Device" opens the chat after the first start, with a button to add an LLM provider instead of the LLM settings

## 1.1.1 (2026-11-06)

- feat: the model can search all repositories of a chat at once
- feat: the model can process the results of MCP tools in its JavaScript sandbox
- feat: show live usage (cost / tokens) while the answer is generated
- feat(app): chats are shown as a panel on larger screens, which can be hidden
- feat(app): pages have a limited content width on larger screens
- feat(app): wide tables in answers scroll horizontally
- feat(app): add minimal mcp settings page to enable/disable
- i18n: add Viet

## 1.1.0 (2026-11-04)

- feat: MCP servers give the model more tools, connected with a token or by signing in (managed in the web app)
- feat: restyled message input
- feat(app): warning before leaving a temporary chat
- feat(app): download button for attachments
- feat(web): the repositories and MCP servers chosen for a new chat are remembered for the next one
- fix: a brief tool call no longer flickers back to "Thinking" while an answer is generated
- fix(app): the chat offers models and repositories added or removed in the settings without a restart

## 1.0.3 (2026-11-01)

- feat: the model can run JavaScript in a sandbox with repository files and attachments
- feat: answers are no longer shown in a card, with the model, duration and cost left aligned below
- feat: replace "Thinking" with actual tool calls ("Looking things up", "Calculating")
- feat: improved dialog for the models fetched from an LLM provider
- feat(web): no logo in the navigation drawer on mobile

## 1.0.2 (2026-10-30)

- feat: the model knows the user's local date and time
- feat: model name, duration and cost below an answer fit on one line
- feat(app): smooth text animation while an answer streams
- feat(app): download button for presented files

## 1.0.1 (2026-10-26)

- feat: server information page for admins
- feat: page for older chats
- feat: settings are grouped into app and user settings, with more descriptive subtitles
- feat: edit user name and email separately
- feat: edit first name, full name and "about me" separately
- feat: improved LLM provider form
- feat(app): attach files to chat messages
- feat(app): different background color in temporary chats
- feat(app): enable auto commit from the proposed commit page
- feat(app): set a Mistral OCR key on a local instance
- feat(app): account selection moved into settings
- feat(app): show logo and version number in settings
- feat(app): improved config page
- feat(app): hide the keyboard when sending a message or tapping outside the input
- feat(web): dark theme
- feat(web): different background color in temporary chats
- fix: the model no longer asks to push changes when auto commit is enabled

## 1.0.0 (2026-10-23)

Initial release.
