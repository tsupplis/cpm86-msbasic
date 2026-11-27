"""Create a new, empty ROM BASIC floppy image."""
import argparse


def create(path, size=320):
    version = {320: 1, 720: 2}[size]
    image = bytearray(size * 1024)
    image[:4] = bytes.fromhex('CD 18 EB FE')  # Enter ROM BASIC when booted in A:
    image[8:17] = b'MSBASRAW' + bytes([version])
    image[510:512] = b'\x55\xaa'
    with open(path, 'xb') as disk:
        disk.write(image)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path')
    parser.add_argument('--size', type=int, choices=(320, 720), default=320)
    args = parser.parse_args()
    create(args.path, args.size)
