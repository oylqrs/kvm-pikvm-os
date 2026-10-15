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


shell: $(BUILD_DIR)
	$(MAKE) -C $(BUILD_DIR) shell


os: $(BUILD_DIR)
	rm -rf $(BUILD_DIR)/stages/arch/{pikvm,pikvm-otg-console}
	cp -a stages/arch/{pikvm,pikvm-otg-console} $(BUILD_DIR)/stages/arch
	$(MAKE) -C $(BUILD_DIR) os \
		BUILD_OPTS=' $(BUILD_OPTS) \
			--build-arg PLATFORM=$(PLATFORM) \
			--build-arg OLED=$(call optbool,$(OLED)) \
			--build-arg VERSIONS=$(call fv,ustreamer)/$(call fv,kvmd)/$(call fv,kvmd-webterm)/$(call fv,kvmd-fan) \
			--build-arg FAN=$(call optbool,$(FAN)) \
			--build-arg ROOT_PASSWD=$(ROOT_PASSWD) \
			--build-arg WEBUI_ADMIN_PASSWD=$(WEBUI_ADMIN_PASSWD) \
			--build-arg IPMI_ADMIN_PASSWD=$(IPMI_ADMIN_PASSWD) \
		'


$(BUILD_DIR):
	mkdir -p `dirname $(BUILD_DIR)`
	git clone --depth=1 https://github.com/mdevaev/pi-builder $(BUILD_DIR)


image: $(BUILD_DIR)
	$(eval _dir := images/$(PLATFORM)-$(BOARD)/$(ARCH))
	$(eval _dated := $(PLATFORM)-$(BOARD)-$(ARCH)$(SUFFIX)-$(shell date +%Y%m%d).img)
	$(eval _latest := $(PLATFORM)-$(BOARD)-$(ARCH)$(SUFFIX)-latest.img)
	$(eval _suffix = $(if $(call optbool,$(IMAGE_XZ)),.xz,))
	mkdir -p $(_dir)
	$(MAKE) -C $(BUILD_DIR) image IMAGE=$(shell pwd)/$(_dir)/$(_dated)
	cd $(_dir) && ln -sf $(_dated)$(_suffix) $(_latest)$(_suffix)
	cd $(_dir) && ln -sf $(_dated)$(_suffix).sha1 $(_latest)$(_suffix).sha1


upload:
	rsync -rl --progress images/ $(UPLOAD_USER)@$(UPLOAD_TARGET)
