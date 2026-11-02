#ifndef DX_LEASE_POLICY_H
#define DX_LEASE_POLICY_H
#include <stdbool.h>
enum { DXLeaseFrame = 1u, DXLeaseForeground = 2u, DXLeaseBackgrounded = 4u };
/// Value-ownership compare/restore policy used by production teardown. No whole-settings reset.
unsigned DXLeaseRestoreMask(unsigned changed, unsigned equalsLastWrite, bool sameSceneProcess, bool ownsRegistryEntry);
#endif
