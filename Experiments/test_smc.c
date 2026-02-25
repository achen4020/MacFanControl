// test_smc.c - 测试 SMC 访问
// 编译: clang -framework IOKit -framework CoreFoundation -o test_smc test_smc.c
// 运行: sudo ./test_smc

#include <stdio.h>
#include <string.h>
#include <IOKit/IOKitLib.h>

#define KERNEL_INDEX_SMC 2

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    UInt16 release;
} SMCKeyData_vers_t;

typedef struct {
    UInt16 version;
    UInt16 length;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef char SMCBytes_t[32];

typedef struct {
    UInt32 key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

static io_connect_t conn;

UInt32 _strtoul(char *str, int size, int base) {
    UInt32 total = 0;
    int i;
    for (i = 0; i < size; i++) {
        if (base == 16)
            total += str[i] << (size - 1 - i) * 8;
        else
            total += (unsigned char)(str[i] << (size - 1 - i) * 8);
    }
    return total;
}

kern_return_t SMCOpen(void) {
    kern_return_t result;
    io_iterator_t iterator;
    io_object_t device;

    CFMutableDictionaryRef matchingDictionary = IOServiceMatching("AppleSMC");
    result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator);
    if (result != kIOReturnSuccess) {
        printf("IOServiceGetMatchingServices failed: 0x%x\n", result);
        return result;
    }

    device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (device == 0) {
        printf("No SMC device found\n");
        return kIOReturnNoDevice;
    }

    result = IOServiceOpen(device, mach_task_self(), 0, &conn);
    IOObjectRelease(device);
    if (result != kIOReturnSuccess) {
        printf("IOServiceOpen failed: 0x%x\n", result);
        return result;
    }

    return kIOReturnSuccess;
}

kern_return_t SMCClose() {
    return IOServiceClose(conn);
}

kern_return_t SMCCall(int index, SMCKeyData_t *inputStructure, SMCKeyData_t *outputStructure) {
    size_t structureInputSize = sizeof(SMCKeyData_t);
    size_t structureOutputSize = sizeof(SMCKeyData_t);

    return IOConnectCallStructMethod(conn, index, inputStructure, structureInputSize,
                                     outputStructure, &structureOutputSize);
}

kern_return_t SMCReadKey(UInt32 key, SMCKeyData_t *result) {
    kern_return_t ret;
    SMCKeyData_t inputStructure;
    SMCKeyData_t outputStructure;

    memset(&inputStructure, 0, sizeof(SMCKeyData_t));
    memset(&outputStructure, 0, sizeof(SMCKeyData_t));

    inputStructure.key = key;
    inputStructure.data8 = 9;  // kSMCGetKeyInfo

    ret = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    inputStructure.keyInfo.dataSize = outputStructure.keyInfo.dataSize;
    inputStructure.data8 = 5;  // kSMCReadKey

    ret = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    memcpy(result, &outputStructure, sizeof(SMCKeyData_t));
    return kIOReturnSuccess;
}

int main(int argc, char *argv[]) {
    kern_return_t result;
    SMCKeyData_t data;

    printf("SMC Test (C version)\n");
    printf("====================\n");
    printf("UID: %d\n", getuid());
    printf("SMCKeyData_t size: %lu\n", sizeof(SMCKeyData_t));

    result = SMCOpen();
    if (result != kIOReturnSuccess) {
        printf("SMCOpen failed: 0x%x\n", result);
        return 1;
    }
    printf("SMC connection opened\n");

    // 测试读取 FNum
    printf("\nTrying to read FNum...\n");
    UInt32 key = _strtoul("FNum", 4, 16);
    result = SMCReadKey(key, &data);
    if (result == kIOReturnSuccess) {
        printf("FNum: %d fans\n", data.bytes[0]);
    } else {
        printf("FNum failed: 0x%x\n", result);
    }

    // 测试读取 F0Ac
    printf("\nTrying to read F0Ac...\n");
    key = _strtoul("F0Ac", 4, 16);
    result = SMCReadKey(key, &data);
    if (result == kIOReturnSuccess) {
        UInt16 rpm = (data.bytes[0] << 8) | data.bytes[1];
        printf("F0Ac: %d RPM\n", rpm / 4);
    } else {
        printf("F0Ac failed: 0x%x\n", result);
    }

    SMCClose();
    printf("\nDone\n");
    return 0;
}
