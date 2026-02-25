// test_smc3.c - 查看原始 SMC 数据
// 编译: clang -framework IOKit -framework CoreFoundation -o test_smc3 test_smc3.c
// 运行: sudo ./test_smc3

#include <stdio.h>
#include <string.h>
#include <IOKit/IOKitLib.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_KEYINFO 9
#define SMC_CMD_READ_KEY 5

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

UInt32 _strtoul(const char *str, int size, int base) {
    UInt32 total = 0;
    for (int i = 0; i < size; i++) {
        total += (unsigned char)str[i] << (size - 1 - i) * 8;
    }
    return total;
}

void _ultostr(char *str, UInt32 val) {
    str[0] = (val >> 24) & 0xFF;
    str[1] = (val >> 16) & 0xFF;
    str[2] = (val >> 8) & 0xFF;
    str[3] = val & 0xFF;
    str[4] = 0;
}

kern_return_t SMCOpen(void) {
    kern_return_t result;
    io_iterator_t iterator;
    io_object_t device;

    CFMutableDictionaryRef matchingDictionary = IOServiceMatching("AppleSMC");
    result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator);
    if (result != kIOReturnSuccess) return result;

    device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (device == 0) return kIOReturnNoDevice;

    result = IOServiceOpen(device, mach_task_self(), 0, &conn);
    IOObjectRelease(device);
    return result;
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

void printRawKey(const char *keyName) {
    kern_return_t ret;
    SMCKeyData_t inputStructure;
    SMCKeyData_t outputStructure;
    char typeStr[5];

    memset(&inputStructure, 0, sizeof(SMCKeyData_t));
    memset(&outputStructure, 0, sizeof(SMCKeyData_t));

    inputStructure.key = _strtoul(keyName, 4, 16);
    inputStructure.data8 = SMC_CMD_READ_KEYINFO;

    ret = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (ret != kIOReturnSuccess) {
        printf("%s: GetKeyInfo FAILED (0x%x)\n", keyName, ret);
        return;
    }

    UInt32 dataSize = outputStructure.keyInfo.dataSize;
    UInt32 dataType = outputStructure.keyInfo.dataType;
    _ultostr(typeStr, dataType);

    printf("%s: size=%u, type='%s' (0x%08X)\n", keyName, dataSize, typeStr, dataType);

    inputStructure.keyInfo.dataSize = dataSize;
    inputStructure.data8 = SMC_CMD_READ_KEY;

    ret = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (ret != kIOReturnSuccess) {
        printf("  ReadKey FAILED (0x%x)\n", ret);
        return;
    }

    // 打印原始字节
    printf("  Raw bytes: ");
    for (int i = 0; i < dataSize && i < 16; i++) {
        printf("%02X ", (unsigned char)outputStructure.bytes[i]);
    }
    printf("\n");

    // 尝试不同的解码方式
    if (dataSize >= 2) {
        // Big-endian 16-bit
        UInt16 be16 = ((unsigned char)outputStructure.bytes[0] << 8) | (unsigned char)outputStructure.bytes[1];
        // Little-endian 16-bit
        UInt16 le16 = ((unsigned char)outputStructure.bytes[1] << 8) | (unsigned char)outputStructure.bytes[0];

        printf("  BE16: %u (fpe2: %.1f)\n", be16, be16 / 4.0);
        printf("  LE16: %u (fpe2: %.1f)\n", le16, le16 / 4.0);
    }

    if (dataSize >= 4) {
        // Big-endian 32-bit
        UInt32 be32 = ((unsigned char)outputStructure.bytes[0] << 24) |
                      ((unsigned char)outputStructure.bytes[1] << 16) |
                      ((unsigned char)outputStructure.bytes[2] << 8) |
                      (unsigned char)outputStructure.bytes[3];
        // Little-endian 32-bit
        UInt32 le32 = ((unsigned char)outputStructure.bytes[3] << 24) |
                      ((unsigned char)outputStructure.bytes[2] << 16) |
                      ((unsigned char)outputStructure.bytes[1] << 8) |
                      (unsigned char)outputStructure.bytes[0];

        // Float
        float flt;
        memcpy(&flt, outputStructure.bytes, 4);

        printf("  BE32: %u, LE32: %u, Float: %.2f\n", be32, le32, flt);
    }

    printf("\n");
}

int main(int argc, char *argv[]) {
    printf("SMC Raw Data Test\n");
    printf("=================\n");
    printf("UID: %d\n\n", getuid());

    if (SMCOpen() != kIOReturnSuccess) {
        printf("SMCOpen failed\n");
        return 1;
    }

    printf("--- Fan Keys ---\n");
    printRawKey("FNum");
    printRawKey("F0Ac");
    printRawKey("F0Mn");
    printRawKey("F0Mx");
    printRawKey("F0Tg");
    printRawKey("F0Sf");
    printRawKey("F0Md");
    printRawKey("FS! ");
    printRawKey("Ftst");

    printf("--- Temperature Keys ---\n");
    printRawKey("TC0P");
    printRawKey("TC0D");
    printRawKey("Tp01");
    printRawKey("Tp02");

    SMCClose();
    printf("Done\n");
    return 0;
}
