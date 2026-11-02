#include "DXABIEncoding.h"
#include "DXLeasePolicy.h"
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static unsigned checks;
static void match(const char *a, const char *b, bool expected) {
    assert(DXABIEncodingMatches(a,b)==expected); ++checks;
}
int main(void) {
    match("v24@0:8@16","v@:@",true);
    match("v40@0:8@16@24@?32","v@:@@@?",true);
    match("@16@0:8","@@:",true);
    match("@32@0:8@16Q24","@@:@Q",true);
    match("B24@0:8@16","B@:@",true);
    match("{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8","{CGRect={CGPoint=dd}{CGSize=dd}}@:",true);
    match("v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16","v@:{CGRect={CGPoint=dd}{CGSize=dd}}",true);
    match("v32@0:8{CGPoint=dd}16","v@:{CGPoint=dd}",true);
    match("v24@0:8@?16","v@:@",false);  // Block must not masquerade as id.
    match("c16@0:8","B@:",false);       // BOOL/char mismatch must be rejected.
    match("I16@0:8","i@:",false);
    match("Q16@0:8","q@:",false);
    match("@24@0:8@16","@@:",false);
    match("v24@0:8@16","v@:@@",false);
    match("v24@0:8r^v16","v@:^v",false);
    match("{CGRect={CGPoint=ff}{CGSize=ff}}16@0:8","{CGRect={CGPoint=dd}{CGSize=dd}}@:",false);
    match("{NSRect={CGPoint=dd}{CGSize=dd}}16@0:8","{CGRect={CGPoint=dd}{CGSize=dd}}@:",false);
    match("v24@0:8@\"FBScene\"16","v@:@",false); // No loose token rewriting.
    match("v24@0:8^@16","v@:@",false);
    match("v@:[4i]","v@:[4i]",true);
    match("v@:[4i]","v@:[8i]",false);
    match("v@:{Pair=ii}","v@:{Pair=ii}",true);
    match("v@:{Pair=ii","v@:{Pair=ii",false);
    match("v@:\"oops","v@:\"oops",false);
    match("v@:?garbage","v@:?garbage",false);
    match("v24@0:8+","v@:",false);
    match(NULL,"v@:",false); match("","",false);
    char large[4200]; memset(large,'v',sizeof large); large[sizeof large-1]=0;
    match(large,large,false);
    // Production restore policy: exhaustive masks and ownership combinations.
    for (unsigned changed=0;changed<16;changed++) for (unsigned equal=0;equal<16;equal++)
        for (unsigned same=0;same<2;same++) for (unsigned owned=0;owned<2;owned++) {
            unsigned expected=same && owned ? changed & equal & 7u : 0;
            assert(DXLeaseRestoreMask(changed,equal,same,owned)==expected); ++checks;
        }
    // Deterministic malformed-input corpus against the production parser, including deep nesting.
    uint32_t state=0x44585331;
    const char alphabet[]="v@:?{}[]()^rib0123456789\"+-=XYZ";
    for (unsigned n=0;n<20000;n++) {
        char sample[160]; state=state*1664525u+1013904223u;
        unsigned len=(state>>16)%159;
        for (unsigned i=0;i<len;i++) { state=state*1664525u+1013904223u; sample[i]=alphabet[(state>>16)%(sizeof alphabet-1)]; }
        sample[len]=0;
        (void)DXABIEncodingMatches(sample,"v@:@?");
        (void)DXABIEncodingMatches(sample,sample); ++checks;
    }
    printf("PASS: %u production ABI/lease/corpus checks (C only; no iOS runtime claims)\n",checks);
    return 0;
}
