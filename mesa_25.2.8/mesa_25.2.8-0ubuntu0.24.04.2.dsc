-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA512

Format: 3.0 (quilt)
Source: mesa
Binary: libgbm1, libgbm-dev, libegl-mesa0, libegl1-mesa-dev, libgles2-mesa-dev, libglx-mesa0, libgl1-mesa-dri, libgl1-mesa-dev, mesa-common-dev, mesa-libgallium, mesa-teflon-delegate, mesa-va-drivers, mesa-vdpau-drivers, mesa-vulkan-drivers, mesa-opencl-icd, mesa-drm-shim
Architecture: any
Version: 25.2.8-0ubuntu0.24.04.2
Maintainer: Ubuntu Developers <ubuntu-devel-discuss@lists.ubuntu.com>
Uploaders: Andreas Boll <aboll@debian.org>
Homepage: https://mesa3d.org/
Standards-Version: 4.1.4
Vcs-Browser: https://salsa.debian.org/xorg-team/lib/mesa
Vcs-Git: https://salsa.debian.org/xorg-team/lib/mesa.git
Testsuite: autopkgtest
Testsuite-Triggers: build-essential, pkg-config
Build-Depends: debhelper-compat (= 13), directx-headers-dev (>= 1.614.1) [linux-amd64 linux-arm64], flatbuffers-compiler [linux-arm64], glslang-tools [amd64 arm64 armel armhf i386 loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x sparc64 x32], spirv-tools (>= 2025.1~rc1) [amd64 arm64 armel armhf i386 loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x sparc64 x32], meson-1.7 (>= 1.7.0), pkgconf, libdrm-dev (>= 2.4.125-1), libx11-dev, libxxf86vm-dev, libexpat1-dev, libflatbuffers-dev [linux-arm64], libsensors-dev [!hurd-any], libxext-dev, libva-dev (>= 1.6.0) [linux-any] <!pkg.mesa.nolibva>, libvdpau-dev (>= 1.5) [linux-any], libvulkan-dev [amd64 arm64 armel armhf i386 loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x sparc64 x32], x11proto-dev, linux-libc-dev (>= 2.6.31) [linux-any], libx11-xcb-dev, libxcb-dri2-0-dev (>= 1.8), libxcb-glx0-dev (>= 1.8.1), libxcb-dri3-dev, libxcb-present-dev, libxcb-randr0-dev, libxcb-shm0-dev, libxcb-sync-dev, libxrandr-dev, libxshmfence-dev (>= 1.1), libxtensor-dev [linux-arm64], libzstd-dev, python3, python3-mako, python3-yaml, python3-pycparser [arm64 armhf], python3-setuptools, flex, bison, libelf-dev [amd64 arm64 armel armhf i386 loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x sparc64 x32], libwayland-dev (>= 1.15.0) [linux-any], libwayland-egl-backend-dev (>= 1.15.0) [linux-any], llvm-20-dev [amd64 arm64 armel armhf i386 loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x sparc64 x32], libclang-20-dev [amd64 arm64 armel armhf i386 loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x sparc64 x32], libclang-cpp20-dev [amd64 arm64 armel armhf i386 loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x sparc64 x32], libclc-20-dev [amd64 arm64 armel armhf i386 loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x sparc64 x32], libclc-20 [amd64 arm64 armel armhf i386 loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x sparc64 x32], wayland-protocols (>= 1.41), zlib1g-dev, libglvnd-core-dev (>= 1.3.2), valgrind [amd64 arm64 armhf i386 mips64el powerpc ppc64 ppc64el s390x], rustc-1.78 (>= 1.78) [amd64 arm64 armel armhf loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x x32], rustfmt-1.78 [amd64 arm64 armel armhf loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x x32], bindgen-0.71 (>= 0.71~) [amd64 arm64 armel armhf loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x x32], cbindgen [amd64 arm64 armel armhf loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x x32], llvm-spirv-20 [amd64 arm64 armel armhf loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x x32], libllvmspirvlib-20-dev [amd64 arm64 armel armhf i386 loong64 mips64el powerpc ppc64 ppc64el riscv64 s390x sparc64 x32]
Package-List:
 libegl-mesa0 deb libs optional arch=any
 libegl1-mesa-dev deb libdevel optional arch=any
 libgbm-dev deb libdevel optional arch=linux-any
 libgbm1 deb libs optional arch=linux-any
 libgl1-mesa-dev deb oldlibs optional arch=any
 libgl1-mesa-dri deb libs optional arch=any
 libgles2-mesa-dev deb oldlibs optional arch=any
 libglx-mesa0 deb libs optional arch=any
 mesa-common-dev deb libdevel optional arch=any
 mesa-drm-shim deb libs optional arch=amd64,arm64,armel,armhf,i386,mips64el,powerpc,ppc64,ppc64el,s390x,sparc64
 mesa-libgallium deb libs optional arch=linux-any
 mesa-opencl-icd deb libs optional arch=amd64,arm64,armel,armhf,loong64,mips64el,powerpc,ppc64,ppc64el,riscv64,s390x,x32
 mesa-teflon-delegate deb libs optional arch=arm64
 mesa-va-drivers deb libs optional arch=linux-any profile=!pkg.mesa.nolibva
 mesa-vdpau-drivers deb libs optional arch=linux-any
 mesa-vulkan-drivers deb libs optional arch=amd64,arm64,armel,armhf,i386,loong64,mips64el,powerpc,ppc64,ppc64el,riscv64,s390x,sparc64,x32
Checksums-Sha1:
 fdc5142bf0deb9888e153bb086122581c4a3bedc 43813260 mesa_25.2.8.orig.tar.xz
 a88e9ac0dcfe22a18c4f29704e21eae6d5c22e12 488 mesa_25.2.8.orig.tar.xz.asc
 df53b362ac0de7c9d94aa2d43bade740aabe02da 406124 mesa_25.2.8-0ubuntu0.24.04.2.debian.tar.xz
Checksums-Sha256:
 097842f3e49d996868b38688db87b006f7d4541e93ce86d2f341d8b3e7be7c93 43813260 mesa_25.2.8.orig.tar.xz
 dd9135ba5282d345eb029f99e7e089886eec26fa34d1471dfcd13a77f43fe33e 488 mesa_25.2.8.orig.tar.xz.asc
 0a9571bb53628d9fb934e8f02bbbe7e7fb411fece5f46f3cc50a7aa7f2615e5b 406124 mesa_25.2.8-0ubuntu0.24.04.2.debian.tar.xz
Files:
 c555052c29e6fdfe3cfb68c05707ca09 43813260 mesa_25.2.8.orig.tar.xz
 d312876369bd9cd3ae13ffc84530a2e7 488 mesa_25.2.8.orig.tar.xz.asc
 638bab5f16823a1adfb4437d263f31e4 406124 mesa_25.2.8-0ubuntu0.24.04.2.debian.tar.xz
Original-Maintainer: Debian X Strike Force <debian-x@lists.debian.org>

-----BEGIN PGP SIGNATURE-----

iQIzBAEBCgAdFiEEUMSg3c8x5FLOsZtRZWnYVadEvpMFAmoQZCgACgkQZWnYVadE
vpMy6Q//cKhS1tTRYzdi6M345+kjwisgnyyH3sxa+kpyEkK9HOuCJ/fh4bMMqNsT
xDG4nPmsuLHvCzmN0CYV+rkqfNI6RbaqcZPBRm3p0IFlu8FZ+RCm9LKvtFyIZKzM
dfeTA9Iy8Y9DZZlyi2VWXToFpoTCagZzhOx2Wn69S63bD6G4MAe6U7k3eDgFUnnJ
0g3YCAhX1HQMJQ51g7/+S4/mzb04SX1SQvUMwrNIzuxlxmbuZc51Rx1U/gQ2bj54
D9hYKoI10LLMUyXCPs49pLl3qc/hHYUX0d9q3+L1AomzTi+TX6V12G0dVx4lfJ7C
M2p8H5kLktjTpP/RFRDB23UIUCP/SmIq96DD9z8gL39jWsepMkUaggapWyR/SRd4
ecviQ3qc9ylRqC9y52NRzqZpqkZ8uCJKwoYqth6OHJHRimb5AfJzeprGNdr0GbDb
WdLiRJab3WLVEQtaf6Ix13d2zXL5hH60SjqhoyymLH46Sxaaqf/RtwJq4GSmrUoE
5yj4TbDMcn/LmzMjfvZ9Rm5H3v7340La1dcKrL0qeUvFH2mx+fCXmNphq7IDZMOD
Msg+RiQWdAGrNSe0Vgpe4Ih24DE98JEeEiZihDP7jeNCTdOfoZweDgN/RJ6VgW2m
Throma63xGutAcuWY9Nx1v3aHKGn6deVt3PLmnz93l0cIAZ5HRk=
=2lvs
-----END PGP SIGNATURE-----
