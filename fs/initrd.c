#include <fs/fs.h>
#include <stdint.h>
#include <stddef.h>
#include <arch/bootinfo.h>
#include <errno.h>
#include <mm/heap.h>
#include <mm/paging.h>
#include <mm/memset.h>
#include <print.h>

struct cpioHeader {
	char magic[6];
	char ino[8];
	char mode[8];
	char uid[8];
	char gid[8];
	char nlink[8];
	char mtime[8];
	char filesize[8];
	char devmajor[8];
	char devminor[8];
	char rdevmajor[8];
	char rdevminor[8];
	char namesize[8];
	char check[8];
};

static char cpioMagic[6] = "070701";
static char cpioEndName[] = "TRAILER!!!";

struct superBlock ramfsSuperBlock = {
	.fsID = 1
};

static uint32_t parseHex(char *str) {
	uint32_t result = 0;
	for (int i = 0; i < 8; i++) {
		if (str[i] >= 'A') {
			result += (str[i] - 'A' + 10) << (28 - (i*4));
		} else {
			result += (str[i] - '0') << (28 - (i*4));
		}
	}
	return result;
}

static int parseInitrd(struct inode *rootInode) {
	//char *initrd = bootInfo.initrd;
	char *initrd = ioremap((uintptr_t)bootInfo.initrd, bootInfo.initrdLen);
	struct cpioHeader *initrdHeader;
	unsigned long curPosition = 0;
	while (curPosition < bootInfo.initrdLen) {
		initrdHeader = (struct cpioHeader *)(&initrd[curPosition]);
		if (!memcmp(initrdHeader->magic, cpioMagic, 6)) {
			printk("Invalid CPIO header: %s\n", initrdHeader->magic);
			return -EINVAL;
		}
		uint32_t nameLen = parseHex(initrdHeader->namesize);
		char *name = &initrd[curPosition + sizeof(struct cpioHeader)];
		if (nameLen == sizeof(cpioEndName) && memcmp(name, cpioEndName, sizeof(cpioEndName))) {
			break;
		}
		
		//TODO add support for directories (and hardlinks?)

		printk("Add file: %s\n", name);
		struct inode *newInode = kmalloc(sizeof(struct inode));
		newInode->cachedData = name + nameLen;
		uint32_t fileSize = parseHex(initrdHeader->filesize);
		newInode->fileSize = fileSize;

		int error = fsLink(rootInode, newInode, name);
		if (error) {
			return error;
		}

		curPosition += sizeof(struct cpioHeader) + nameLen + fileSize;
		if (curPosition & 3) {
			curPosition &= ~3;
			curPosition += 4;
		}
	}
	
	return 0;
}

int ramfsInit(void) {
	//register driver

	if (!bootInfo.initrd) {
		return 0;
	}
	//create root inode
	struct inode *rootInode = kmalloc(sizeof(struct inode));
	if (!rootInode) {
		return -ENOMEM;
	}
	memset(rootInode, 0, sizeof(struct inode));

	rootInode->inodeID = 1;
	rootInode->type = ITYPE_DIR;
	rootInode->refCount = 1;
	rootInode->nrofLinks = 1;
	rootInode->ramfs = RAMFS_PRESENT;
	rootInode->superBlock = &ramfsSuperBlock;
	rootInode->attr.accessPermissions = 0664;

	mountRoot(rootInode);
	ramfsSuperBlock.curInodeID = 2;

	return parseInitrd(rootInode);
}