#############################################################
#
# klish
# http://libcode.org/attachments/52/klish-2.0.2.tar.xz
# http://libcode.org/attachments/download/52/klish-2.0.2.tar.xz
#############################################################

KLISH_VERSION = 2.0.2
KLISH_SOURCE = klish-$(KLISH_VERSION).tar.xz
KLISH_SITE = http://libcode.org/attachments/download/52

KLISH_DEPENDENCIES =
KLISH_CONF_OPT = --disable-gpl --without-tcl

ifeq ($(BR2_PACKAGE_LIBROXML),y)
KLISH_DEPENDENCIES += libroxml
KLISH_CONF_OPT += --with-libroxml
endif

ifeq ($(BR2_PACKAGE_LIBXML2),y)
KLISH_DEPENDENCIES += libxml2
KLISH_CONF_OPT += --with-libxml2
endif

ifeq ($(BR2_PACKAGE_EXPAT),y)
KLISH_DEPENDENCIES += expat
KLISH_CONF_OPT += --with-libexpat
endif

$(eval $(autotools-package))
