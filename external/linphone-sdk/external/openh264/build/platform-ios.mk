ARCH = armv7
include $(SRC_PATH)build/platform-darwin.mk
CXX = clang++
CC = clang
TARGET_OPTION=

ifeq ($(SDKTYPE),)
	#the following is wrong since arm64 is also a simulator architecture.
	ifneq ($(filter %86 x86_64, $(ARCH)),)
		SDKTYPE="iPhoneSimulator"
	else
		SDKTYPE="iPhoneOS"
	endif
endif


ifeq ($(SDKTYPE),iPhoneSimulator)
	TARGET_OPTION="$(ARCH)-apple-ios-simulator"
else
	TARGET_OPTION="$(ARCH)-apple-ios"
endif


SDK_MIN = 5.1

SDKROOT := $(shell xcrun --sdk $(shell echo $(SDKTYPE) | tr A-Z a-z) --show-sdk-path)
CFLAGS += -target $(TARGET_OPTION) -arch $(ARCH) -isysroot $(SDKROOT) -miphoneos-version-min=$(SDK_MIN) -DAPPLE_IOS -fembed-bitcode
LDFLAGS += -target $(TARGET_OPTION) -arch $(ARCH) -isysroot $(SDKROOT) -miphoneos-version-min=$(SDK_MIN)

