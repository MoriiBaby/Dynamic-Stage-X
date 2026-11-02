#ifndef DX_ABI_ENCODING_H
#define DX_ABI_ENCODING_H
#include <stdbool.h>
/// Exact ObjC type tokens, ignoring only numeric method stack sizes/offsets.
/// Does NOT equate BOOL/char, block/id, signedness, qualifiers, pointers or struct names.
bool DXABIEncodingMatches(const char *runtimeEncoding, const char *expectedEncoding);
#endif
