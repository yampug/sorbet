#include "common/common.h"
#include "main/options/options.h"
#include "main/realmain.h"
#include <cstdio>
#include <exception>

int main(int argc, char *argv[]) {
    try {
        return sorbet::realmain::realmain(argc, argv);
    } catch (sorbet::EarlyReturnWithCode &c) {
        return c.returnCode;
    } catch (std::exception &e) {
        fprintf(stderr, "Caught exception: %s\n", e.what());
        return 1;
    } catch (...) {
        fprintf(stderr, "Caught unknown exception\n");
        return 1;
    }
};
