ASM=nasm
BUILD_DIR=./build
BUILD_SUBDIR=/output
SRC_DIR=./src

img := $(BUILD_DIR)/main.img

all:
	mkdir -p $(BUILD_DIR)
	$(ASM) -f bin $(SRC_DIR)/bootloader/stage1.asm -o $(BUILD_DIR)/stage1.bin
	$(ASM) -f bin $(SRC_DIR)/bootloader/stage2.asm -o $(BUILD_DIR)/stage2.bin

	rm -f $(img)
	dd if=/dev/zero of=$(img) count=8 bs=1M
	
	dd if=$(BUILD_DIR)/stage1.bin of=$(img) conv=notrunc 
	dd if=$(BUILD_DIR)/stage2.bin of=$(img) conv=notrunc seek=1

	qemu-system-x86_64 -drive format=raw,file=$(img),if=ide
	

clean:
	rm -rf $(BUILD_DIR)

