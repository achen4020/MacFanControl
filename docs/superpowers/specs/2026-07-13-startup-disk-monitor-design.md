# 启动磁盘监控设计

## 背景

当前菜单把 HID 温度通道放在“更多传感器”展开区。新的界面不再展示通道明细，而是只保留能明确对应设备的 SSD 温度，并增加当前 macOS 启动磁盘的容量和使用率。

## 目标

- 完全移除“更多传感器”按钮和展开内容。
- 精确读取 `NAND CH0 temp`，作为独立的 `SSD 温度` 行；不存在时隐藏。
- 统计当前 macOS 启动卷 `/` 的总容量、已用容量和使用率。
- 显示 `已用 / 总容量` 和百分比，并按使用率着色。
- 磁盘统计失败时不显示错误数据，也不影响温度和风扇控制。

## 数据模型

在 `MacFanControlCore` 中新增 `StorageUsage`：

- `used: UInt64`
- `available: UInt64`
- `total: UInt64`
- `percentage: Double`
- 已用和总容量的格式化文本

初始化时验证 `total > 0`、`available <= total`，并由 `total - available` 计算已用容量，避免无效值和整数下溢。

## 存储监控

在 `SystemMonitor.swift` 新增 `StorageMonitor`，默认路径为 `/`。使用 `FileManager.attributesOfFileSystem(forPath:)` 获取：

- `.systemSize`：启动卷总容量。
- `.systemFreeSize`：启动卷可用容量。

监控结果缓存 30 秒。现有两秒监控循环可以持续调用，但只有缓存到期后才访问文件系统。读取失败或属性无效时返回 `nil`。

## SSD 温度

`FanController` 增加可选的 `ssdTemperature`：

- Apple Silicon HID 路径只接受名称精确等于 `NAND CH0 temp` 的读数。
- Intel/SMC 回退路径不显示 SSD 温度；其 `SSD` 标签对应另一条 SMC key，不能冒充已验证的 NAND 传感器。
- 本次读取没有 SSD 温度时将属性设为 `nil`，避免继续显示过期值。

## 界面

温度区域移除 `showMoreSensors` 状态及全部展开列表代码，新增两行：

- `SSD 温度`：使用硬盘图标和现有温度着色规则。
- `SSD 存储`：显示 `已用 / 总容量（百分比）`，使用率达到 50%、75%、90% 时依次使用黄色、橙色、红色。

CPU、最高温度、CPU 使用率、内存和 GPU 行保持不变。

## 测试

- 容量模型正确计算已用容量和百分比。
- 零容量、可用容量超过总容量时拒绝创建。
- GB/TB 格式化结果稳定。
- SSD 温度名称保持精确匹配，未知通道不用于 SSD 温度。

## 非目标

- 不统计外接磁盘或所有内部磁盘合计。
- 不区分 APFS 容器内的 System、Data 和 Preboot 卷。
- 不实现磁盘读写速度、健康状态或 SMART 信息。
