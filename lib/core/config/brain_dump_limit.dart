/// Build My Day input limit used only until the server's `max_input_words` (from /ai/status) arrives, or when it
/// cannot be reached. The server is the authority and enforces it; keep this equal to
/// `BMD_MAX_INPUT_WORDS` in backend/app/core/economy_config.py.
const int kDefaultBrainDumpMaxWords = 200;

/// Mirror of `BMD_MAX_INPUT_CHARS` (words x 8): the backstop for text without spaces.
const int kBrainDumpCharsPerWord = 8;
