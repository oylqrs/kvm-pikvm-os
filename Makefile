-include config.mk # 如果config.mk不存在就静默忽略

PLATFORM ?= v2-hdmi#目标硬件平台，默认 v2-hdm
SUFFIX ?= #项目名后缀，默认为空，用于区分自定义构建。
export BOARD ?= rpi4#目标板型，默认 rpi4  export：传递给子 Make 进程
export ARCH ?= arm #CPU 架构，默认 arm（32 位）
export PROJECT ?= pikvm-os.$(PLATFORM)$(SUFFIX) #PROJECT：项目名，由 PLATFORM 和 SUFFIX 拼接
export STAGES ?= __init__ os pikvm-repo pistat watchdog rootdelay ro pikvm restore-mirrorlist __cleanup__ #构建阶段序列，按顺序执行：
#__init__ 初始化 → os 装基础系统 → pikvm-repo 配软件源 → pistat 装状态监控 → watchdog 装看门狗 → rootdelay 设根延迟 → ro 设只读 → pikvm 装核心包 → restore-mirrorlist 恢复镜像源 → __cleanup__ 清理


export NC ?= #NC：默认为空，透传给 pi-builder 的额外控制变量

export HOSTNAME ?= pikvm#系统主机名，默认 pikvm
export LOCALE ?= en_US#系统语言环境，默认 en_US
export TIMEZONE ?= UTC#系统时区，默认 UTC
export ARCH_DIST_REPO_URL ?= http://de3.mirror.archlinuxarm.org#Arch Linux ARM 软件包镜像源。de3. 前缀有时会导致下载失败
BUILD_OPTS ?= #额外传给 pi-builder 的构建选项，默认为空

ROOT_PASSWD ?= root#Linux root 密码，默认 root
WEBUI_ADMIN_PASSWD ?= admin#WEBUI_ADMIN_PASSWD ?= admin
IPMI_ADMIN_PASSWD ?= admin#IPMI 管理员密码，默认 admin

export DISK ?= $(shell pwd)/disk/$(word 1,$(subst -, ,$(PLATFORM))).conf#DISK：分区配置文件路径  $(subst -, ,$(PLATFORM))：把 v2-hdmi 中的 - 替换成空格 → v2 hdmi  $(word 1,...)：取第一个词 → v2 最终路径：当前目录/disk/v2.conf  
export CARD ?= /dev/null#make install 时的目标 SD 卡设备，默认 /dev/null 防止误写
export IMAGE_XZ ?=#是否生成 .xz 压缩镜像，默认为空（不压缩）

UPLOAD_USER ?= root#make upload 时的远程用户名，默认 root
UPLOAD_TARGET ?= files.pikvm.org:/var/www/files.pikvm.org/images#make upload 时的远程目标地址

BUILD_DIR ?= ./.pi-builder#pi-builder 工具链的克隆位置


# =====
SHELL := bash#指定用 bash 执行命令
.SHELLFLAGS := -Eeuo pipefail -c#bash 严格模式：E ERR trap 继承到子 shell -e 命令失败立即退出-u 未定义变量报错-o pipefail 管道任一命令失败即失败-c 执行字符串命令

define optbool#定义 optbool 函数开始
$(filter $(shell echo $(1) | tr A-Z a-z),yes on 1)#把参数转小写，过滤出 yes、on、1 中的一个  用途：把 OLED=yes 转成 yes 传给 Docker
endef#函数定义结束

define fv#定义 fv 函数开始
$(shell curl --silent "https://files.pikvm.org/repos/arch/$(BOARD)-$(ARCH)/latest/$(1)")#向官方服务器查询指定软件包的最新版本号
endef


# =====
all:#默认目标。直接运行 make 时触发
	@ echo "Available commands:"   #打印标题。@ 表示不回显命令本身
	@ echo "    make                # Print this help"
	@ echo "    make os             # Build OS with your default config"
	@ echo "    make shell          # Run Arch-ARM shell"
	@ echo "    make install        # Install rootfs to partitions on $(CARD)"
	@ echo "    make image          # Create a binary image for burning outside of make install"
	@ echo "    make scan           # Find all RPi devices in the local network"
	@ echo "    make clean          # Remove the generated rootfs"
	@ echo "    make clean-all      # Remove the generated rootfs and pi-builder toolchain"


shell: $(BUILD_DIR)#shell 目标，依赖 $(BUILD_DIR)
	$(MAKE) -C $(BUILD_DIR) shell#进入 pi-builder 目录，执行它的 shell 目标


os: $(BUILD_DIR)#os 目标，依赖 $(BUILD_DIR)
	rm -rf $(BUILD_DIR)/stages/arch/{pikvm,pikvm-otg-console}#删除构建目录里旧的 pikvm 和 pikvm-otg-console 阶段文件
	cp -a stages/arch/{pikvm,pikvm-otg-console} $(BUILD_DIR)/stages/arch#把本仓库 stages/arch/ 下的这两个目录复制到构建目录
	$(MAKE) -C $(BUILD_DIR) os \#进入 pi-builder 目录，执行它的 os 目标。反斜杠表示命令续行
		BUILD_OPTS=' $(BUILD_OPTS) \#传入构建参数，开头拼接用户自定义的 BUILD_OPTS
			--build-arg PLATFORM=$(PLATFORM) \#传入平台参数
			--build-arg OLED=$(call optbool,$(OLED)) \#传入 OLED 开关，经 optbool 转换  
			--build-arg VERSIONS=$(call fv,ustreamer)/$(call fv,kvmd)/$(call fv,kvmd-webterm)/$(call fv,kvmd-fan) \#查询并传入四个组件的版本号，用 / 拼接---这就是多仓库整合的核心机制
			--build-arg FAN=$(call optbool,$(FAN)) \#传入风扇控制开关
			--build-arg ROOT_PASSWD=$(ROOT_PASSWD) \#传入 root 密码
			--build-arg WEBUI_ADMIN_PASSWD=$(WEBUI_ADMIN_PASSWD) \#传入 Web UI 管理员密码
			--build-arg IPMI_ADMIN_PASSWD=$(IPMI_ADMIN_PASSWD) \#传入 IPMI 管理员密码
		'


$(BUILD_DIR):#定义 $(BUILD_DIR) 目标，用于自动克隆 pi-builder
	mkdir -p `dirname $(BUILD_DIR)`#创建 BUILD_DIR 的父目录
	git clone --depth=1 https://github.com/mdevaev/pi-builder $(BUILD_DIR)#浅克隆 pi-builder 仓库到 BUILD_DIR


image: $(BUILD_DIR)#image 目标，依赖 $(BUILD_DIR)
	$(eval _dir := images/$(PLATFORM)-$(BOARD)/$(ARCH))#动态定义输出目录，如 images/v2-hdmi-rpi4/arm/
	$(eval _dated := $(PLATFORM)-$(BOARD)-$(ARCH)$(SUFFIX)-$(shell date +%Y%m%d).img)#动态定义带日期的镜像文件名
	$(eval _latest := $(PLATFORM)-$(BOARD)-$(ARCH)$(SUFFIX)-latest.img)#动态定义最新镜像的软链接名
	$(eval _suffix = $(if $(call optbool,$(IMAGE_XZ)),.xz,))#如果 IMAGE_XZ 为真，后缀为 .xz，否则为空
	mkdir -p $(_dir)#创建输出目录
	$(MAKE) -C $(BUILD_DIR) image IMAGE=$(shell pwd)/$(_dir)/$(_dated)#调用 pi-builder 的 image 目标，传入镜像输出路径
	cd $(_dir) && ln -sf $(_dated)$(_suffix) $(_latest)$(_suffix)#创建 -latest.img 软链接，指向带日期的文件
	cd $(_dir) && ln -sf $(_dated)$(_suffix).sha1 $(_latest)$(_suffix).sha1#创建 -latest.img.sha1 软链接


upload:#upload 目标，无依赖，直接执行
	rsync -rl --progress images/ $(UPLOAD_USER)@$(UPLOAD_TARGET)#用 rsync 把 images/ 内容增量上传到远程服务器  -r 递归，-l 保留软链接，--progress 显示进度。 展开后：rsync -rl --progress images/ root@files.pikvm.org:/var/www/files.pikvm.org/images
