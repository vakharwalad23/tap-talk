#import "ObjCExceptions.h"

NSException *_Nullable tt_catch_exception(NS_NOESCAPE void (^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}
