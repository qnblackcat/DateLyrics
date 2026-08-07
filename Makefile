TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = Music SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DateLyrics
DateLyrics_FILES = DateLyrics.xm
DateLyrics_CFLAGS = -fobjc-arc

SUBPROJECTS = DateLyricsPrefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

# Normalise permissions in the staging tree before the .deb is built.
#
# A restrictive umask on the build host otherwise ships every file as 600 and every
# directory as 700. Those modes survive into the package, and since SpringBoard,
# PreferenceLoader and Preferences all run as `mobile`, the result is a tweak that
# never injects and a settings pane that fails with "error loading preference
# bundle (null)". Fixing it here means the archive is correct by construction
# rather than repaired after the fact by layout/DEBIAN/postinst.
before-package::
	@echo "> Normalising staging permissions"
	@find "$(THEOS_STAGING_DIR)" -type d -exec chmod 755 {} +
	@find "$(THEOS_STAGING_DIR)" -type f -exec chmod 644 {} +
	@find "$(THEOS_STAGING_DIR)" -type f -name '*.dylib' -exec chmod 755 {} +
	@find "$(THEOS_STAGING_DIR)" -type f -path '*/DateLyricsPrefs.bundle/DateLyricsPrefs' -exec chmod 755 {} +
	@for script in postinst postrm preinst prerm; do \
		if [ -f "$(THEOS_STAGING_DIR)/DEBIAN/$$script" ]; then \
			chmod 755 "$(THEOS_STAGING_DIR)/DEBIAN/$$script"; \
		fi; \
	done
