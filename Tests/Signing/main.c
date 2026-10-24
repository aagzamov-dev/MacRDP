#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <stdio.h>
#include <string.h>

#ifndef BUILD_VERSION
#define BUILD_VERSION 1
#endif

int main(int argc, const char *argv[]) {
    if (argc != 3 || strncmp(argv[1], "uz.macrdp.signing-test.", sizeof("uz.macrdp.signing-test.") - 1) != 0) return 2;
    SecKeychainSetUserInteractionAllowed(false);
    CFStringRef service = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, service);
    CFDictionarySetValue(query, kSecAttrAccount, CFSTR("synthetic-fixture"));
    const UInt8 value[] = "synthetic-signing-regression-value";
    OSStatus status = errSecParam;
    if (strcmp(argv[2], "write") == 0) {
        CFDataRef data = CFDataCreate(NULL, value, sizeof(value));
        CFDictionarySetValue(query, kSecValueData, data);
        status = SecItemAdd(query, NULL);
        CFRelease(data);
    } else if (strcmp(argv[2], "read") == 0) {
        CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
        CFTypeRef result = NULL;
        status = SecItemCopyMatching(query, &result);
        if (status == errSecSuccess && (!result || CFGetTypeID(result) != CFDataGetTypeID() ||
            CFDataGetLength(result) != sizeof(value) || memcmp(CFDataGetBytePtr(result), value, sizeof(value)) != 0)) status = errSecDecode;
        if (result) CFRelease(result);
    } else if (strcmp(argv[2], "delete") == 0) {
        status = SecItemDelete(query);
        if (status == errSecItemNotFound) status = errSecSuccess;
    }
    CFRelease(query); CFRelease(service);
    if (status != errSecSuccess) fprintf(stderr, "Signing fixture v%d failed with OSStatus %d (interaction disabled).\n", BUILD_VERSION, (int)status);
    return status == errSecSuccess ? 0 : 1;
}
