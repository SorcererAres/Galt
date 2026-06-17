APP_NAME = Galt
DIST = dist/$(APP_NAME).app
# App 图标源：放一张 1024×1024 PNG 到此路径，`make app` 会自动生成 .icns 并嵌入
ICON_SRC = Resources/AppIcon.png
# 固定签名身份，保证重新编译后辅助功能等授权尽量不失效；缺失时回退 ad-hoc。
# 优先使用项目专用证书，其次使用本机第一张有效代码签名证书。
SIGN_ID := $(shell \
	if security find-identity -v -p codesigning 2>/dev/null | grep -q "Galt Dev Signing"; then \
		echo "Galt Dev Signing"; \
	else \
		security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' | head -1; \
	fi)
SIGN_ID := $(if $(strip $(SIGN_ID)),$(SIGN_ID),-)

.PHONY: build app run dmg clean

build:
	swift build -c release

app: build
	rm -rf $(DIST)
	mkdir -p $(DIST)/Contents/MacOS $(DIST)/Contents/Resources $(DIST)/Contents/Frameworks
	cp Resources/Info.plist $(DIST)/Contents/Info.plist
	cp .build/release/$(APP_NAME) $(DIST)/Contents/MacOS/$(APP_NAME)
	cp -R Vendor/whisper.xcframework/macos-arm64_x86_64/whisper.framework $(DIST)/Contents/Frameworks/
	install_name_tool -add_rpath @executable_path/../Frameworks $(DIST)/Contents/MacOS/$(APP_NAME) 2>/dev/null || true
	@if [ -f "$(ICON_SRC)" ]; then \
		echo "生成 App 图标 …"; \
		rm -rf build/AppIcon.iconset; mkdir -p build/AppIcon.iconset; \
		for sz in 16 32 128 256 512; do \
			d=$$((sz*2)); \
			sips -z $$sz $$sz "$(ICON_SRC)" --out build/AppIcon.iconset/icon_$${sz}x$${sz}.png >/dev/null; \
			sips -z $$d $$d "$(ICON_SRC)" --out build/AppIcon.iconset/icon_$${sz}x$${sz}@2x.png >/dev/null; \
		done; \
		iconutil -c icns build/AppIcon.iconset -o $(DIST)/Contents/Resources/AppIcon.icns; \
	else \
		echo "⚠️  未找到 $(ICON_SRC)，App 图标将缺省。把 1024×1024 PNG 放到该路径后重跑 make app。"; \
	fi
	codesign --force --timestamp=none --sign "$(SIGN_ID)" $(DIST)/Contents/Frameworks/whisper.framework
	codesign --force --timestamp=none --sign "$(SIGN_ID)" $(DIST)
	@echo "已生成 $(DIST)"

run: app
	open $(DIST)

dmg: app
	rm -f dist/$(APP_NAME).dmg
	hdiutil create -volname $(APP_NAME) -srcfolder $(DIST) -ov -format UDZO dist/$(APP_NAME).dmg
	@echo "已生成 dist/$(APP_NAME).dmg"

clean:
	rm -rf .build dist
