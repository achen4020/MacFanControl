// test_temp.c - 测试温度读取
#include <stdio.h>
#include <string.h>
#include <IOKit/IOKitLib.h>

#define KERNEL_INDEX_SMC 2

typedef struct {
    char major; char minor; char build; char reserved[1]; UInt16 release;
} SMCKeyData_vers_t;

typedef struct {
    UInt16 version; UInt16 length; UInt32 cpuPLimit; UInt32 gpuPLimit; UInt32 memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    UInt32 dataSize; UInt32 dataType; char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef struct {
    UInt32 key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result; char status; char data8;
    UInt32 data32;
    char bytes[32];
} SMCKeyData_t;

static io_connect_t conn = 0;

UInt32 strToKey(const char *str) {
    return ((unsigned char)str[0] << 24) | ((unsigned char)str[1] << 16) |
           ((unsigned char)str[2] << 8) | (unsigned char)str[3];
}

int main() {
    printf("Temperature Key Test\n");

    io_iterator_t iter;
    IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iter);
    io_object_t dev = IOIteratorNext(iter);
    IOObjectRelease(iter);

    if (IOServiceOpen(dev, mach_task_self(), 0, &conn) != kIOReturnSuccess) {
        printf("Cannot open SMC\n");
        return 1;
    }
    IOObjectRelease(dev);

    const char *keys[] = {"Tp01", "Tp02", "Tp05", "Tp09", "TC0P", "TC0D", NULL};

    for (int i = 0; keys[i]; i++) {
        SMCKeyData_t in = {0}, out = {0};
        size_t outSize = sizeof(out);

        in.key = strToKey(keys[i]);
        in.data8 = 9;  // GetKeyInfo

        kern_return_t ret = IOConnectCallStructMethod(conn, 2, &in, sizeof(in), &out, &outSize);
        printf("%s: GetKeyInfo ret=0x%x, size=%u, type=0x%08X\n",
               keys[i], ret, out.keyInfo.dataSize, out.keyInfo.dataType);

        if (ret == kIOReturnSuccess && out.keyInfo.dataSize > 0) {
            in.keyInfo.dataSize = out.keyInfo.dataSize;
            in.data8 = 5;  // ReadKey

            ret = IOConnectCallStructMethod(conn, 2, &in, sizeof(in), &out, &outSize);
            if (ret == kIOReturnSuccess) {
                float temp;
                memcpy(&temp, out.bytes, 4);
                printf("  -> %.1f°C (bytes: %02X %02X %02X %02X)\n",
                       temp, (unsigned char)out.bytes[0], (unsigned char)out.bytes[1],
                       (unsigned char)out.bytes[2], (unsigned char)out.bytes[3]);
            }
        }
    }

    IOServiceClose(conn);
    return 0;
}
