#include "DXLeasePolicy.h"
unsigned DXLeaseRestoreMask(unsigned changed, unsigned equalsLastWrite, bool sameSceneProcess, bool ownsRegistryEntry) {
    return sameSceneProcess && ownsRegistryEntry ? changed & equalsLastWrite & 7u : 0u;
}
