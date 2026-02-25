// test_smc2.c - 完整的 SMC 风扇测试
// 编译: clang -framework IOKit -framework CoreFoundation -o test_smc2 test_smc2.c
// 运行: sudo ./test_smc2

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
    if (result != kIOReturnSuccess) {
        return result;
    }

    device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (device == 0) {
        return kIOReturnNoDevice;
    }

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

kern_return_t SMCReadKey(const char *key, SMCKeyData_t *result) {
    kern_return_t ret;
    SMCKeyData_t inputStructure;
    SMCKeyData_t outputStructure;

    memset(&inputStructure, 0, sizeof(SMCKeyData_t));
    memset(&outputStructure, 0, sizeof(SMCKeyData_t));

    inputStructure.key = _strtoul(key, 4, 16);
    inputStructure.data8 = SMC_CMD_READ_KEYINFO;

    ret = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    inputStructure.keyInfo.dataSize = outputStructure.keyInfo.dataSize;
    inputStructure.data8 = SMC_CMD_READ_KEY;

    ret = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    memcpy(result, &outputStructure, sizeof(SMCKeyData_t));
    return kIOReturnSuccess;
}

// 解码 fpe2 格式 (fixed point 14.2)
float decodeFPE2(unsigned char *bytes) {
    UInt16 raw = ((UInt16)bytes[0] << 8) | bytes[1];
    return raw / 4.0f;
}

// 解码 sp78 格式 (signed fixed point 7.8)
float decodeSP78(unsigned char *bytes) {
    SInt16 raw = ((SInt16)bytes[0] << 8) | bytes[1];
    return raw / 256.0f;
}

int main(int argc, char *argv[]) {
    kern_return_t result;
    SMCKeyData_t data;
    char typeStr[5];

    printf("SMC Fan Control Test\n");
    printf("====================\n");
    printf("UID: %d\n", getuid());

    result = SMCOpen();
    if (result != kIOReturnSuccess) {
        printf("SMCOpen failed: 0x%x\n", result);
        return 1;
    }
    printf("SMC connection opened\n\n");

    // 读取风扇数量
    printf("--- Fan Information ---\n");
    result = SMCReadKey("FNum", &data);
    if (result == kIOReturnSuccess) {
        int fanCount = data.bytes[0];
        printf("Number of fans: %d\n\n", fanCount);

        // 读取每个风扇的信息
        for (int i = 0; i < fanCount; i++) {
            char key[5];
            printf("Fan %d:\n", i);

            // 当前转速 F%dAc
            sprintf(key, "F%dAc", i);
            result = SMCReadKey(key, &data);
            if (result == kIOReturnSuccess) {
                _ultostr(typeStr, data.keyInfo.dataType);
                float rpm = decodeFPE2((unsigned char*)data.bytes);
                printf("  Current Speed: %.0f RPM (type: %s)\n", rpm, typeStr);
            } else {
                printf("  Current Speed: FAILED (0x%x)\n", result);
            }

            // 最小转速 F%dMn
            sprintf(key, "F%dMn", i);
            result = SMCReadKey(key, &data);
            if (result == kIOReturnSuccess) {
                float rpm = decodeFPE2((unsigned char*)data.bytes);
                printf("  Min Speed: %.0f RPM\n", rpm);
            }

            // 最大转速 F%dMx
            sprintf(key, "F%dMx", i);
            result = SMCReadKey(key, &data);
            if (result == kIOReturnSuccess) {
                float rpm = decodeFPE2((unsigned char*)data.bytes);
                printf("  Max Speed: %.0f RPM\n", rpm);
            }

            // 目标转速 F%dTg
            sprintf(key, "F%dTg", i);
            result = SMCReadKey(key, &data);
            if (result == kIOReturnSuccess) {
                float rpm = decodeFPE2((unsigned char*)data.bytes);
                printf("  Target Speed: %.0f RPM\n", rpm);
            }

            // 安全转速 F%dSf
            sprintf(key, "F%dSf", i);
            result = SMCReadKey(key, &data);
            if (result == kIOReturnSuccess) {
                float rpm = decodeFPE2((unsigned char*)data.bytes);
                printf("  Safe Speed: %.0f RPM\n", rpm);
            }

            printf("\n");
        }
    } else {
        printf("FNum failed: 0x%x\n", result);
    }

    // 读取一些温度
    printf("--- Temperature Sensors ---\n");
    const char *tempKeys[] = {"TC0P", "TC0D", "TC0E", "TC0F", "TC1C", "Tp01", "Tp02", NULL};

    for (int i = 0; tempKeys[i] != NULL; i++) {
        result = SMCReadKey(tempKeys[i], &data);
        if (result == kIOReturnSuccess) {
            _ultostr(typeStr, data.keyInfo.dataType);
            float temp = decodeSP78((unsigned char*)data.bytes);
            printf("  %s: %.1f°C (type: %s)\n", tempKeys[i], temp, typeStr);
        }
    }

    // 检查 Ftst (fan test mode)
    printf("\n--- Fan Control Status ---\n");
    result = SMCReadKey("Ftst", &data);
    if (result == kIOReturnSuccess) {
        printf("  Ftst (Fan Test Mode): %d\n", data.bytes[0]);
    } else {
        printf("  Ftst: FAILED (0x%x)\n", result);
    }

    result = SMCReadKey("FS! ", &data);
    if (result == kIOReturnSuccess) {
        printf("  FS!  (Fan Speed Forced): 0x%02X%02X\n",
               (unsigned char)data.bytes[0], (unsigned char)data.bytes[1]);
    }

    SMCClose();
    printf("\nDone\n");
    return 0;
}
