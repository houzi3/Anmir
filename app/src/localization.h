#ifndef SC_LOCALIZATION_H
#define SC_LOCALIZATION_H

// Message identifiers are stable English source strings. The English table
// may evolve independently; identifiers must not be used as business state.
// Returned strings remain valid across language changes (including async SDL
// dialogs). Standalone/non-macOS clients fall back to the source string.
const char *sc_localize(const char *key);

#endif
