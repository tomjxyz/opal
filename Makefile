APP      := Opal
SRCS     := src/main.cpp src/opal.cpp src/chatclient.cpp src/history.cpp src/httpjob.cpp src/imagetool.cpp src/json.cpp src/jpegtool.c src/crash.c
MOC_HDRS := src/opal.h src/chatclient.h src/history.h src/imagetool.h
# Qt/Cascades app: rules.mk adds Qt flags/libs and uses Dinkumware libcpp (what Qt is built with)
CASCADES := 1
# -g/-funwind-tables: crash reports from src/crashlog.h can be symbolised against the binary
CFLAGS   += -g -funwind-tables
CXXFLAGS += -g -funwind-tables
LIBS     := -lcurl -lbbcascadesmultimedia -lbbcascadespickers -lbbplatform -lcamapi -ljpeg -lcrypto
EXTRA_ASSETS := $(wildcard assets/*) icon.png
# BB10: root of the BlackBerry 10 build kit holding examples/common/rules.mk (the bb10-sdk image sets it)
BB10 ?= ../..
include $(BB10)/examples/common/rules.mk
