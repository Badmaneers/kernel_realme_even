#!/bin/bash
# Origami Kernel Builder - Badmaneers Edition
# A versatile script to build, configure, and package the Saturn-Kernel for Realme C25 and Narzo50A (Even) with ease.
# Define some things
# Kernel common
export ARCH=arm64
export version=-V1.8
export LINKER="ld.lld"
export kver="release-candidate"
export CODENAME="even"
export DEVICE="Realme C25 and Narzo50A (${CODENAME})"
export BUILDER="DumbDragon"
export BUILD_HOST="localHost"
export TIMESTAMP=$(date +"%Y%m%d")-$(date +"%H%M%S")
export KBUILD_COMPILER_STRING=$(./clang/bin/clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')
export FW="RUI4"
export zipn="Saturn-Kernel-${FW}-${TIMESTAMP}"
export LLVM=1 
export LLVM_IAS=1
# Needed by script
export PATH="${PWD}/clang/bin:${PATH}"
PROCS=$(nproc --all)

# Get the script's own filename
SCRIPT_NAME=$(basename "$0")

# Toolchain & AnyKernel repos
export CLANG_REPO="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86"
export CLANG_BRANCH="main"
export ANYKERNEL_REPO="https://github.com/osm0sis/AnyKernel3.git"
export ANYKERNEL_BRANCH="master"

# Text coloring
NOCOLOR='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHTGRAY='\033[0;37m'
DARKGRAY='\033[1;30m'
LIGHTRED='\033[1;31m'
LIGHTGREEN='\033[1;32m'
YELLOW='\033[1;33m'
LIGHTBLUE='\033[1;34m'
LIGHTPURPLE='\033[1;35m'
LIGHTCYAN='\033[1;36m'
WHITE='\033[1;37m'

# Check permission
script_permissions=$(stat -c %a "$0")
if [ "$script_permissions" -lt 777 ]; then
    echo -e "${RED}error:${NOCOLOR} Don't have enough permission"
    echo "run 'chmod 0777 $SCRIPT_NAME' and rerun"
    exit 126
fi

# Check dependencies
if ! hash make curl bc zip 2>/dev/null; then
        echo -e "${RED}error:${NOCOLOR} Environment has missing dependencies"
        echo "Install make, curl, bc, and zip !"
        exit 127
fi

# Exit while got interrupt signal
exit_on_signal_interrupt() {
    echo -e "\n\n${RED}Got interrupt signal.${NOCOLOR}"
    exit 130
}
trap exit_on_signal_interrupt SIGINT

help_msg() {
    echo "Usage: bash origami_kernel_builder.sh --choose=[Function]"
    echo ""
    echo "Some functions on Origami Kernel Builder:"
    echo "1. Build a whole Kernel"
    echo "2. Regenerate defconfig"
    echo "3. Open menuconfig"
    echo "4. Clean"
    echo ""
    echo "Place this script inside the Kernel Tree."
}

clone_dependencies() {

    echo -e "${LIGHTBLUE}Checking dependencies...${NOCOLOR}"

    # ===============================
    # Google Clang
    # ===============================
    if [ ! -d "${PWD}/clang" ]; then
        echo -e "${CYAN}Clang not found. Cloning latest Google Clang...${NOCOLOR}"
        
        git clone --depth=1 ${CLANG_REPO} -b ${CLANG_BRANCH} clang-temp || exit 1
        
        # Move highest version folder to ./clang
        LATEST_CLANG=$(ls clang-temp | grep clang-r | sort -V | tail -n1)
        mv clang-temp/$LATEST_CLANG clang
        rm -rf clang-temp

        echo -e "${GREEN}Google Clang (${LATEST_CLANG}) cloned.${NOCOLOR}"
    else
        echo -e "${GREEN}Clang already exists. Skipping clone.${NOCOLOR}"
    fi

    # ===============================
    # AnyKernel
    # ===============================
    if [ ! -d "${PWD}/anykernel" ]; then
        echo -e "${CYAN}AnyKernel not found. Cloning...${NOCOLOR}"
        git clone --depth=1 ${ANYKERNEL_REPO} -b ${ANYKERNEL_BRANCH} anykernel || exit 1
        echo -e "${GREEN}AnyKernel cloned.${NOCOLOR}"
    else
        echo -e "${GREEN}AnyKernel already exists. Skipping clone.${NOCOLOR}"
    fi
}

show_defconfigs() {
    defconfig_path="./arch/${ARCH}/configs"

    # Check if folder exists
    if [ ! -d "$defconfig_path" ]; then
        echo -e "${RED}FATAL:${NOCOLOR} Seems not a valid Kernel linux"
        exit 2
    fi

    echo -e "Available defconfigs:\n"

    # List defconfigs and assign them to an array
    defconfigs=($(ls "$defconfig_path"))

    # Display enumerated defconfigs
    for ((i=0; i<${#defconfigs[@]}; i++)); do
        echo -e "${LIGHTCYAN}$i: ${defconfigs[i]}${NOCOLOR}"
    done

    echo ""
    read -p "Select the defconfig you want to process: " choice

    # Check if the choice is within the range of files
    if [ $choice -ge 0 ] && [ $choice -lt ${#defconfigs[@]} ]; then
        export DEFCONFIG="${defconfigs[choice]}"
        echo "Selected defconfig: $DEFCONFIG"

        # Detect device variant from defconfig name
        if [[ "$DEFCONFIG" == *"c25"* || "$DEFCONFIG" == *"C25"* ]]; then
            export DEVICE_SUFFIX="-C25"
            export localversion=${version}-C25
        else
            export DEVICE_SUFFIX="-Even"
            export localversion=${version}-Even
        fi

        # Update zip name accordingly
        export zipn="Saturn-Kernel${DEVICE_SUFFIX}-${FW}-${TIMESTAMP}"
    else
        echo -e "${RED}error:${NOCOLOR} Invalid choice"
        exit 1
    fi
}

check_incremental() {

    if [ -f "out/.config" ]; then
        echo "Previous build detected."
        read -p "Use incremental build? (Y/n): " ans
        ans=${ans:-y}

        if [[ "${ans,,}" != "y" ]]; then
            echo "Cleaning build output..."
            make clean
            make mrproper
            rm -rf out
        fi
    fi
}

compile_kernel() {
    rm ./out/arch/${ARCH}/boot/Image.gz-dtb 2>/dev/null

    export KBUILD_BUILD_USER=${BUILDER}
    export KBUILD_BUILD_HOST=${BUILD_HOST}
    export LOCALVERSION=${localversion}

    make O=out ARCH=${ARCH} ${DEFCONFIG}

    START=$(date +"%s")

    make -j"$PROCS" O=out \
        ARCH=${ARCH} \
        LD="${LINKER}" \
        AR=llvm-ar \
        AS=llvm-as \
        NM=llvm-nm \
        OBJDUMP=llvm-objdump \
        STRIP=llvm-strip \
        CC="clang" \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabihf- \
        CONFIG_NO_ERROR_ON_MISMATCH=y \
        CONFIG_DEBUG_SECTION_MISMATCH=y \
        V=0 2>&1 SKIP_DTBO_CHECK=true | tee out/build.log

    END=$(date +"%s")
    DIFF=$((END - START))
    export minutes=$((DIFF / 60))
    export seconds=$((DIFF % 60))
}

generate_banner() {

    echo "Generating banner..."

    mkdir -p anykernel

    cat << 'EOF' > anykernel/banner
                                         _.oo.
                 _.u[[/;:,.         .odMMMMMM'
              .o888UU[[[/;:-.  .o@P^    MMM^
             oN88888UU[[[/;::-.        dP^
            dNMMNN888UU[[[/;:--.   .o@P^
           ,MMMMMMN888UU[[/;::-. o@^
           NNMMMNN888UU[[[/~.o@P^
           888888888UU[[[/o@^-..
          oI8888UU[[[/o@P^:--..
       .@^  YUU[[[/o@^;::---..
     oMP     ^/o@P^;:::---..
  .dMMM    .o@^ ^;::---...
 dMMMMMMM@^`       `^^^^
YMMMUP^
 ^^
EOF

}

# ===============================
# CONFIGURE ANYKERNEL
# ===============================
configure_anykernel() {

    ANYKERNEL_SH="anykernel/anykernel.sh"

    echo "Configuring AnyKernel..."


    # ===============================
    # Kernel string
    # ===============================
    sed -i "s|kernel.string=.*|kernel.string=Saturn-Kernel ${version} by ${BUILDER}|g" $ANYKERNEL_SH

    # ===============================
    # Device names
    # ===============================
    sed -i "s|device.name1=.*|device.name1=RMX3430|g" $ANYKERNEL_SH
    sed -i "s|device.name2=.*|device.name2=RMX3191|g" $ANYKERNEL_SH
    sed -i "s|device.name3=.*|device.name3=RMX3193|g" $ANYKERNEL_SH
    sed -i "s|device.name4=.*|device.name4=RMX3195|g" $ANYKERNEL_SH
    sed -i "s|device.name5=.*|device.name5=RMX3197|g" $ANYKERNEL_SH
    sed -i "s|device.name6=.*|device.name6=${CODENAME}|g" $ANYKERNEL_SH

    # ===============================
    # Block & slot config
    # ===============================
    sed -i "s|^BLOCK=.*|BLOCK=/dev/block/by-name/boot;|g" $ANYKERNEL_SH
    sed -i "s|^IS_SLOT_DEVICE=.*|IS_SLOT_DEVICE=0;|g" $ANYKERNEL_SH

    # ===============================
    # Modules auto detection
    # ===============================
    if [ -d "out/lib/modules" ]; then
        sed -i "s|do.modules=.*|do.modules=1|g" $ANYKERNEL_SH
    else
        sed -i "s|do.modules=.*|do.modules=0|g" $ANYKERNEL_SH
    fi
}

zip_kernel() {

    IMG_DTB="./out/arch/${ARCH}/boot/Image.gz-dtb"
    IMG="./out/arch/${ARCH}/boot/Image.gz"

    # Copy correct image
    if [ -f "$IMG_DTB" ]; then
        cp "$IMG_DTB" ./anykernel/
        IMAGE_NAME="Image.gz-dtb"
    elif [ -f "$IMG" ]; then
        cp "$IMG" ./anykernel/
        IMAGE_NAME="Image.gz"
    else
        echo "❌ Kernel image not found!"
        exit 1
    fi

    # Generate banner file first
    generate_banner

    # Configure AnyKernel dynamically
    configure_anykernel

    # Create zip
    cd ./anykernel || exit 1
    zip -r9 "${zipn}.zip" * -x .git README.md *placeholder
    cd ..

    # Generate checksum
    checksum=$(sha512sum "./anykernel/${zipn}.zip" | cut -d ' ' -f1)

    # Create target directory
    mkdir -p ./out/target

    # Remove copied image from anykernel
    rm -f "./anykernel/${IMAGE_NAME}"

    # Move final zip
    mv "./anykernel/${zipn}.zip" ./out/target/

    echo "✅ Kernel Zip Created: out/target/${zipn}.zip"
    echo "🔐 SHA512: ${checksum}"
}

build_kernel() {
    clone_dependencies
    show_defconfigs

    echo -e "${LIGHTBLUE}================================="
    echo "Build Started on ${BUILD_HOST}"
    echo "Build status: ${kver}"
    echo "Builder: ${BUILDER}"
    echo "Device: ${DEVICE}"
    echo "Kernel Version: $(make kernelversion 2>/dev/null)"
    echo "Date: $(date)"
    echo "Zip Name: ${zipn}"
    echo "Defconfig: ${DEFCONFIG}"
    echo "Compiler: ${KBUILD_COMPILER_STRING}"
    echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "Last Commit: $(git log --format="%s" -n 1): $(git log --format="%h" -n 1)"
    echo -e "=================================${NOCOLOR}"

    check_incremental
    compile_kernel

    if [ ! -f "./out/arch/${ARCH}/boot/Image.gz-dtb" ] && [ ! -f "./out/arch/${ARCH}/boot/Image.gz" ]; then

        echo -e "${LIGHTBLUE}================================="
        echo -e "${RED}Build failed${LIGHTBLUE} after ${minutes} minutes and ${seconds} seconds"
        echo "See build log for troubleshooting."
        echo -e "=================================${NOCOLOR}"
        exit 1
    fi

    zip_kernel

    echo -e "${LIGHTBLUE}================================="
    echo "Build took ${minutes} minutes and ${seconds} seconds."
    echo "SHA512: ${checksum}"
    echo "Kernel zip: ${zipn}.zip"
    echo -e "=================================${NOCOLOR}"
}

regen_defconfig() {
show_defconfigs
make O=out ARCH=${ARCH} ${DEFCONFIG}
cp -rf ./out/.config ./arch/${ARCH}/configs/${DEFCONFIG}
}

open_menuconfig() {
show_defconfigs
make O=out ARCH=${ARCH} ${DEFCONFIG}
echo -e "${LIGHTGREEN}Note: Make sure you save the config with name '.config'"
echo -e "      else the defconfig will not saved automatically.${NOCOLOR}"
local count=3
while [ $count -gt 0 ]; do
    echo -ne -e "${LIGHTCYAN}menuconfig will be opened in $count seconds... \r${NOCOLOR}"
    sleep 1
    ((count--))
done
make O=out menuconfig
cp -rf ./out/.config ./arch/${ARCH}/configs/${DEFCONFIG}
}

execute_operation() {

   loop_helper() {
      read -p "Press enter to continue or type 0 for Quit: " a1
      clear
      if [[ "$a1" == "0" ]]; then
          exit 0
      else
          bash "$0"
      fi
   }

   case "$1" in
        1) clear
            build_kernel
            loop_helper
            ;;
        2) clear
            regen_defconfig
            loop_helper
             ;;
        3) clear
             open_menuconfig
             loop_helper
             ;;
        4) clear
            make clean && make mrproper
            loop_helper
            ;;
        5) exit 0 && clear ;;
        6) help_msg ;;
        *) echo -e "${RED}error:${NOCOLOR} Invalid selection." && exit 1 ;;
    esac
}

if [ $# -eq 0 ]; then
    clear
    echo -e "${LIGHTCYAN}What do you want to do today?"
    echo ""
    echo "1. Build a whole Kernel"
    echo "2. Regenerate defconfig"
    echo "3. Open menuconfig"
    echo "4. Clean"
    echo "5. Quit"
    echo -e "${NOCOLOR}"
    read -p "Choice the number: " choice
else
    case "$1" in
        --choose=1)
            choice=1
            ;;
        --choose=2)
            choice=2
            ;;
        --choose=3)
            choice=3
            ;;
        --choose=4)
            choice=4
            ;;
        --help)
            choice=6
            ;;
        *)
            echo -e "${RED}error:${NOCOLOR} Not a valid argument"
            echo "Try 'bash origami_kernel_builder.sh --help' for more information."
            exit 1
            ;;
    esac
fi

# Main script logic
execute_operation "$choice"
