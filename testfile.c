#include <stdio.h>

int main() {
    // #region with comment text
    // #region
    // nested region
    // #endregion
    printf("Hello World\n");
    // #endregion comment doesn't need to match
    
    // #region fold folded on initial open
    // #endregion
    return 0;
}
