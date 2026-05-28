from datetime import datetime


def main():
    now = datetime.now().strftime("%H:%M:%S")
    print("测试脚本运行成功")
    print(f"当前时间 {now}")
    print("加班 2.5 小时")


if __name__ == "__main__":
    main()
