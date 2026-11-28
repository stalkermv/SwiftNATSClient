#ifndef SWIFT_NATS_SHIM_H
#define SWIFT_NATS_SHIM_H

#include "../nats.c/src/nats.h"

// On success, the caller owns the seed copy borrowed by options and their clones.
natsStatus swiftNATS_SetUserNKey(natsOptions *options, const char *seed, char **ownedSeed);
void swiftNATS_DestroyNKeySeed(char *seed);

#endif
