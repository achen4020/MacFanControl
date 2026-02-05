// smc_helper.c - SMC Helper Tool for M4 Mac
// 支持两种模式:
// 1. 命令行模式: sudo ./smc_helper info/speed/auto/temp
// 2. Daemon 模式: ./smc_helper daemon (通过 Unix socket 通信)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <signal.h>
#include <IOKit/IOKitLib.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_KEYINFO 9
#define SMC_CMD_READ_KEY 5
#define SMC_CMD_WRITE_KEY 6

#define SOCKET_PATH "/var/run/com.macfancontrol.smchelper.sock"
#define BUFFER_SIZE 4096

typedef struct {
    char major; char minor; char build; char reserved[1]; UInt16 release;
} SMCKeyData_vers_t;

typedef struct {
    UInt16 version; UInt16 length; UInt32 cpuPLimit; UInt32 gpuPLimit; UInt32 memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    UInt32 dataSize; UInt32 dataType; char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef char SMCBytes_t[32];

typedef struct {
    UInt32 key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result; char status; char data8;
    UInt32 data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

static io_connect_t conn = 0;
static int server_fd = -1;
static volatile int running = 1;

UInt32 strToKey(const char *str) {
    return ((unsigned char)str[0] << 24) | ((unsigned char)str[1] << 16) |
           ((unsigned char)str[2] << 8) | (unsigned char)str[3];
}

void keyToStr(UInt32 key, char *str) {
    str[0] = (key >> 24) & 0xFF;
    str[1] = (key >> 16) & 0xFF;
    str[2] = (key >> 8) & 0xFF;
    str[3] = key & 0xFF;
    str[4] = 0;
}

kern_return_t SMCOpen(void) {
    if (conn != 0) return kIOReturnSuccess;
    io_iterator_t iterator;
    io_object_t device;
    CFMutableDictionaryRef matchingDictionary = IOServiceMatching("AppleSMC");
    kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator);
    if (result != kIOReturnSuccess) return result;
    device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (device == 0) return kIOReturnNoDevice;
    result = IOServiceOpen(device, mach_task_self(), 0, &conn);
    IOObjectRelease(device);
    return result;
}

kern_return_t SMCClose(void) {
    if (conn != 0) { IOServiceClose(conn); conn = 0; }
    return kIOReturnSuccess;
}

kern_return_t SMCCall(SMCKeyData_t *input, SMCKeyData_t *output) {
    size_t inSize = sizeof(SMCKeyData_t);
    size_t outSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, input, inSize, output, &outSize);
}

kern_return_t SMCReadKey(const char *keyStr, SMCKeyData_t *result) {
    SMCKeyData_t input = {0}, output = {0};
    input.key = strToKey(keyStr);
    input.data8 = SMC_CMD_READ_KEYINFO;
    kern_return_t ret = SMCCall(&input, &output);
    if (ret != kIOReturnSuccess) return ret;
    input.keyInfo.dataSize = output.keyInfo.dataSize;
    input.data8 = SMC_CMD_READ_KEY;
    ret = SMCCall(&input, &output);
    if (ret != kIOReturnSuccess) return ret;
    memcpy(result, &output, sizeof(SMCKeyData_t));
    return kIOReturnSuccess;
}

kern_return_t SMCWriteKey(const char *keyStr, SMCKeyData_t *data) {
    SMCKeyData_t input = {0}, output = {0};
    input.key = strToKey(keyStr);
    input.data8 = SMC_CMD_READ_KEYINFO;
    kern_return_t ret = SMCCall(&input, &output);
    if (ret != kIOReturnSuccess) return ret;
    input.keyInfo.dataSize = output.keyInfo.dataSize;
    input.data8 = SMC_CMD_WRITE_KEY;
    memcpy(input.bytes, data->bytes, sizeof(input.bytes));
    return SMCCall(&input, &output);
}

float readFloat(unsigned char *bytes) {
    float value;
    memcpy(&value, bytes, 4);
    return value;
}

void writeFloat(unsigned char *bytes, float value) {
    memcpy(bytes, &value, 4);
}

// 命令处理函数
char* cmdInfo(void) {
    static char buffer[BUFFER_SIZE];
    SMCKeyData_t data;

    if (SMCReadKey("FNum", &data) != kIOReturnSuccess) {
        snprintf(buffer, BUFFER_SIZE, "{\"error\": \"Cannot read FNum\"}");
        return buffer;
    }

    int fanCount = data.bytes[0];
    int pos = snprintf(buffer, BUFFER_SIZE, "{\n  \"fanCount\": %d,\n  \"fans\": [\n", fanCount);

    for (int i = 0; i < fanCount; i++) {
        char key[5];
        float current = 0, min = 0, max = 0, target = 0;
        int mode = 0;

        sprintf(key, "F%dAc", i);
        if (SMCReadKey(key, &data) == kIOReturnSuccess)
            current = readFloat((unsigned char*)data.bytes);

        sprintf(key, "F%dMn", i);
        if (SMCReadKey(key, &data) == kIOReturnSuccess)
            min = readFloat((unsigned char*)data.bytes);

        sprintf(key, "F%dMx", i);
        if (SMCReadKey(key, &data) == kIOReturnSuccess)
            max = readFloat((unsigned char*)data.bytes);

        sprintf(key, "F%dTg", i);
        if (SMCReadKey(key, &data) == kIOReturnSuccess)
            target = readFloat((unsigned char*)data.bytes);

        sprintf(key, "F%dMd", i);
        if (SMCReadKey(key, &data) == kIOReturnSuccess)
            mode = data.bytes[0];

        pos += snprintf(buffer + pos, BUFFER_SIZE - pos,
            "    {\"index\": %d, \"currentSpeed\": %.0f, \"minSpeed\": %.0f, \"maxSpeed\": %.0f, \"targetSpeed\": %.0f, \"mode\": %d}%s\n",
            i, current, min, max, target, mode, (i < fanCount - 1) ? "," : "");
    }

    snprintf(buffer + pos, BUFFER_SIZE - pos, "  ]\n}");
    return buffer;
}

char* cmdSetSpeed(float rpm) {
    static char buffer[BUFFER_SIZE];
    SMCKeyData_t data;

    if (SMCReadKey("FNum", &data) != kIOReturnSuccess) {
        snprintf(buffer, BUFFER_SIZE, "{\"error\": \"Cannot read FNum\"}");
        return buffer;
    }

    int fanCount = data.bytes[0];
    for (int i = 0; i < fanCount; i++) {
        char key[5];

        sprintf(key, "F%dMd", i);
        memset(&data, 0, sizeof(data));
        data.bytes[0] = 1;
        SMCWriteKey(key, &data);

        sprintf(key, "F%dTg", i);
        memset(&data, 0, sizeof(data));
        writeFloat((unsigned char*)data.bytes, rpm);
        if (SMCWriteKey(key, &data) != kIOReturnSuccess) {
            snprintf(buffer, BUFFER_SIZE, "{\"error\": \"Cannot set F%dTg\"}", i);
            return buffer;
        }
    }

    snprintf(buffer, BUFFER_SIZE, "{\"success\": true, \"speed\": %.0f}", rpm);
    return buffer;
}

char* cmdAuto(void) {
    static char buffer[BUFFER_SIZE];
    SMCKeyData_t data;

    if (SMCReadKey("FNum", &data) != kIOReturnSuccess) {
        snprintf(buffer, BUFFER_SIZE, "{\"error\": \"Cannot read FNum\"}");
        return buffer;
    }

    int fanCount = data.bytes[0];
    for (int i = 0; i < fanCount; i++) {
        char key[5];
        sprintf(key, "F%dMd", i);
        memset(&data, 0, sizeof(data));
        data.bytes[0] = 0;
        SMCWriteKey(key, &data);
    }

    snprintf(buffer, BUFFER_SIZE, "{\"success\": true}");
    return buffer;
}

char* cmdTemp(void) {
    static char buffer[BUFFER_SIZE];
    SMCKeyData_t data;
    const char *keys[] = {"Tp01", "Tp02", "Tp05", "Tp09", NULL};
    const char *names[] = {"效率核心", "性能核心1", "性能核心2", "性能核心3", NULL};

    int pos = snprintf(buffer, BUFFER_SIZE, "{\n  \"temperatures\": [\n");
    int first = 1;

    for (int i = 0; keys[i] != NULL; i++) {
        SMCKeyData_t input = {0}, output = {0};
        input.key = strToKey(keys[i]);
        input.data8 = SMC_CMD_READ_KEYINFO;

        if (SMCCall(&input, &output) == kIOReturnSuccess && output.keyInfo.dataSize > 0) {
            input.keyInfo.dataSize = output.keyInfo.dataSize;
            input.data8 = SMC_CMD_READ_KEY;

            if (SMCCall(&input, &output) == kIOReturnSuccess) {
                float temp = readFloat((unsigned char*)output.bytes);
                if (temp > 0 && temp < 150) {
                    if (!first) pos += snprintf(buffer + pos, BUFFER_SIZE - pos, ",\n");
                    first = 0;
                    pos += snprintf(buffer + pos, BUFFER_SIZE - pos,
                        "    {\"key\": \"%s\", \"name\": \"%s\", \"value\": %.1f}",
                        keys[i], names[i], temp);
                }
            }
        }
    }

    snprintf(buffer + pos, BUFFER_SIZE - pos, "\n  ]\n}");
    return buffer;
}

// 处理客户端请求
void handleClient(int client_fd) {
    char request[256];
    ssize_t n = read(client_fd, request, sizeof(request) - 1);
    if (n <= 0) return;
    request[n] = '\0';

    // 去除换行符
    char *newline = strchr(request, '\n');
    if (newline) *newline = '\0';

    char *response = NULL;

    if (strcmp(request, "info") == 0) {
        response = cmdInfo();
    } else if (strncmp(request, "speed ", 6) == 0) {
        float rpm = atof(request + 6);
        response = cmdSetSpeed(rpm);
    } else if (strcmp(request, "auto") == 0) {
        response = cmdAuto();
    } else if (strcmp(request, "temp") == 0) {
        response = cmdTemp();
    } else {
        response = "{\"error\": \"Unknown command\"}";
    }

    write(client_fd, response, strlen(response));
}

void signalHandler(int sig) {
    running = 0;
    if (server_fd >= 0) close(server_fd);
    unlink(SOCKET_PATH);
}

// Daemon 模式
int runDaemon(void) {
    struct sockaddr_un addr;

    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);

    // 打开 SMC
    if (SMCOpen() != kIOReturnSuccess) {
        fprintf(stderr, "Cannot open SMC\n");
        return 1;
    }

    // 删除旧的 socket 文件
    unlink(SOCKET_PATH);

    // 创建 socket
    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        return 1;
    }

    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind");
        return 1;
    }

    // 设置 socket 权限，允许所有用户访问
    chmod(SOCKET_PATH, 0666);

    if (listen(server_fd, 5) < 0) {
        perror("listen");
        return 1;
    }

    fprintf(stderr, "SMC Helper daemon started on %s\n", SOCKET_PATH);

    while (running) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) {
            if (running) perror("accept");
            continue;
        }
        handleClient(client_fd);
        close(client_fd);
    }

    SMCClose();
    unlink(SOCKET_PATH);
    return 0;
}

void printUsage(const char *prog) {
    printf("Usage: %s <command> [args]\n", prog);
    printf("Commands:\n");
    printf("  info          - Show fan information (JSON)\n");
    printf("  speed <rpm>   - Set fan speed (RPM)\n");
    printf("  auto          - Reset to automatic control\n");
    printf("  temp          - Show temperatures (JSON)\n");
    printf("  daemon        - Run as daemon (for launchd)\n");
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printUsage(argv[0]);
        return 1;
    }

    // Daemon 模式不需要检查 root
    if (strcmp(argv[1], "daemon") == 0) {
        return runDaemon();
    }

    // 命令行模式需要 root
    if (getuid() != 0) {
        printf("ERROR: Must run as root\n");
        return 1;
    }

    if (SMCOpen() != kIOReturnSuccess) {
        printf("ERROR: Cannot open SMC\n");
        return 1;
    }

    char *result = NULL;

    if (strcmp(argv[1], "info") == 0) {
        result = cmdInfo();
    } else if (strcmp(argv[1], "speed") == 0) {
        if (argc < 3) {
            printf("ERROR: Missing RPM value\n");
            SMCClose();
            return 1;
        }
        result = cmdSetSpeed(atof(argv[2]));
    } else if (strcmp(argv[1], "auto") == 0) {
        result = cmdAuto();
    } else if (strcmp(argv[1], "temp") == 0) {
        result = cmdTemp();
    } else {
        printUsage(argv[0]);
        SMCClose();
        return 1;
    }

    printf("%s\n", result);
    SMCClose();
    return 0;
}
