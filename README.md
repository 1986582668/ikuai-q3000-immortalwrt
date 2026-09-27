# iKuai Q3000 ImmortalWrt 25.12 移植 + 云编译

把 **iKuai Q3000**（MT7981B / 512MB DDR3 / 128MB SPI-NAND）的设备支持，移植到
`tfnhui/immortalwrt-mt798x-25.12`（内核 6.12）源码树上，并用 GitHub Actions 云编译出固件。

## 关键前提

**基座必须用 tfnhui 的 tag，不能用 chasey 上游。**
`build-20260923-130`（commit `7d0c19f`）是与本机路由器正在运行的固件**字节级对应**的那一版；
上游 HEAD 已经多出了 8 个新设备的改动，直接编会出现「一直重启 / 无无线」。

## 设备树的来源

不是从旧 DTS 抄的，而是**从运行中的 Q3000 实时提取**：

```
scp root@192.168.1.1:/sys/firmware/fdt  live.dtb     # 24KB 原始设备树
dtb2dts.py live.dtb live.dts                          # 自研反编译 → 996 行 DTS
```

反编译时用 `__symbols__` 段把 phandle 数值还原成 `&label` 引用，因此得到的
`mt7981b-ikuai-q3000.dts` 在结构上与当初手工移植的原始 source 一致。

与网上流传的 hanwckf 旧 DTS（5.4 内核树）相比，已按实测数据修正：

| 项 | 本移植（实测） | hanwckf 旧版 |
|---|---|---|
| LED | green=pio11 / red=pio10 / blue=pio12，**ACTIVE_HIGH** | ACTIVE_LOW |
| LED 写法 | `function=status` + `color=<LED_COLOR_ID_*>` | `label` |
| 分区 label | `bl2` / `fip` / `ubi`（小写） | `BL2` / `FIP` / `ubi` |
| compatible | `ikuai,q3000`, `mediatek,mt7981` | 多了 `-spim-snand-rfb` |
| MAC | Factory `macaddr@10048`（nvmem-cell） | 无 |

## 仓库结构

```
.github/workflows/build-q3000.yml   云编译工作流
apply.sh                             注入脚本（含基座 md5 守卫）
target/linux/mediatek/
  ├── dts-ext/mt7981b-ikuai-q3000.dts          设备树
  ├── image/filogic-ext.mk                     设备注册（已含 Device/ikuai_q3000）
  └── filogic/base-files/etc/board.d/02_network  板级网络（lan1-3 + wan）
defconfig/ikuai-q3000.config         编译配置（9386 行 / 397 个包）
```

### 配置口径（2026-09-27 起）

`defconfig/ikuai-q3000.config` 以**设备 `/etc/apk/world`（379 条）为唯一基准**一比一复刻，
即「编译出来的固件里有哪些包」= 「当前这台路由器里有哪些包」。

- 关掉 63 个设备上并不存在的包，其中 92% 的体积来自一整套代理工具链
  （`sing-box` 40.9MB / `xray-core` 29.6MB / `v2ray-plugin` 15.9MB /
  `shadowsocks-rust` 12.2MB / `geoview` 7.0MB / `haproxy` 3.8MB），
  另有 btrfs/exfat/ntfs3 全套文件系统工具、coreutils、parted、smartmontools 等。
- 补回 38 个设备实际在用、但原配置漏写的包
  （`htop` / `nano` / `openssh-sftp-server` / `bind-host` / `ddnsto` /
  `watchcat` / `sqm-scripts` / `etherwake` / `iptables-nft` 等）。
- 同时删掉其他 SoC 的引导固件（`trusted-firmware-a-mt7986/7987/7988-*`），
  只保留本机型的 `mt7981` bl2 ×2 + fip。
- 回归校验：多启用 0、漏掉 0；启用总数 397 = 379(world) + 4(引导固件) + 14(构建变体)。

效果：rootfs 65.14MB → 约 32.34MB，sysupgrade 约 36.8MB，overlay 可写空间
约 27MiB 恢复至约 61MiB。

> 注意：`luci-app-openclash` 已在 world 中，故仍保留；被移除的是它的**底层代理内核**
> （`sing-box` / `xray-core` 等）。如需科学上网，刷机后从软件源单独安装即可，
> 不必让每个固件都背上 100MB。

## 编译

推送到 `main` 自动触发，或在 Actions 页面手动 `Run workflow`（可指定 `base_tag`）。

本地复现：

```sh
git clone --depth=1 --branch build-20260923-130 \
  https://github.com/tfnhui/immortalwrt-mt798x-25.12.git openwrt
sh apply.sh openwrt
cd openwrt
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../defconfig/ikuai-q3000.config .config
make defconfig
make download -j8
make -j$(nproc)
```

产物在 `openwrt/bin/targets/mediatek/filogic/`：
- `*squashfs-sysupgrade.bin` — 已在 OpenWrt 上直接升级
- `*squashfs-factory.bin` — 从 U-Boot 刷
- `*initramfs-kernel.bin` — 临时救援

## U-Boot

U-Boot 不在本仓库编译，用 `1986582668/bl-mt798x-dhcpd` 自带的 Actions：
- `BL2-build.yml` — `ATF_VERSION=2025`
- `FIP-build.yml` — `MODEL=mt7981_ikuai_q3000`，`FIP_VERSION=2025`，`VARIANT=default`

产出 `bl2.img` + `fip.bin`。分区布局必须与本仓库 DTS 一致：
`nmbm0:1024k(bl2),512k(u-boot-env),2048k(Factory),2048k(fip),113152k(ubi)`

## 刷机风险提示

- `bl2` / `fip` 刷错会变砖，刷之前先确认路由器已通过 U-Boot 的 TFTP/Web 恢复通道能进。
- 首次刷入建议保留原厂固件备份，或确认能进 U-Boot failsafe。
