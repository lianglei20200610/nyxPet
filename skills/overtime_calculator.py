import os
import re
import json
import calendar
import argparse
import base64
from datetime import date
from datetime import datetime

import sys
sys.path.append(r"C:\Lib")  # 用于指定Python依赖模块路径
import requests
#import pysnooper


QUERY_MON = 5         # 查询的月份
QUERY_YEAR = 2026       # 查询的年份
USERNAME = ""  # 用户名（https://portal.supcon.com），用于登陆EHR
PASSWORD = ""  # 密码（https://portal.supcon.com），用于登陆EHR
BUSINESS_TRIP = 0.0     # 手动输入本月出差加班时间

VERSION = 20230626


#RECORDS_DUMP_FILE = r"D:\records.json"
#WORKDAY_DUMP_FILE = r"D:\workday_info.json"

#RECORDS_DEBUG_FILE = r"D:\records.json"
#WORKDAY_DEBUG_FILE = r"D:\workday_info.json"


userAgent = "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.132 Safari/537.36"
header = {
    "User-Agent": userAgent
}


def main():
    # 初始化
    init()

    # 解析命令行参数
    args = getArgs()

    # 统计启止日期
    begin_date, end_date = getQueryDaysRange(args, QUERY_YEAR, QUERY_MON)

    # 创建Session
    aSession = requests.session()

    # 登陆信息  
    login(aSession, USERNAME, PASSWORD)
    staffId = getStaffId(aSession)

    # 获取打卡数据
    ehrRecords = getEhrRecords(aSession, staffId, begin_date, end_date)

    # 获取班次数据
    workdayInfos = getWorkdayInfos(aSession, staffId, begin_date, end_date)

    # 预处理数据（按日期合并）
    allWorkDays, allKq = prepareData(ehrRecords, workdayInfos)

    # 统计加班时间
    workDayOverHours, holidayOverHours = statData(allWorkDays, allKq)

    # 打印统计数据
    printStatData(workDayOverHours, holidayOverHours)

    # 只有在真实交互命令行里才暂停；桌宠等子进程环境不需要等待按键。
    if sys.stdin.isatty():
        os.system('pause')


def init():
    # 打印程序版本
    print(f'ver: {VERSION}')
    print("--------")


def getArgs():
    global USERNAME, PASSWORD, QUERY_MON, QUERY_YEAR, BUSINESS_TRIP

    parser = argparse.ArgumentParser()
    parser.add_argument('-u', '--username', required=False, help='Username login EHR(https://portal.supcon.com)')
    parser.add_argument('-p', '--password', required=False, help='Passord login EHR(https://portal.supcon.com)')
    parser.add_argument('-qm', '--query_mon', required=False, help='Query month', type=int)
    parser.add_argument('-qy', '--query_year', required=False, help='Query year', type=int)
    parser.add_argument('-qb', '--begin_date', required=False, help='Query begin date')
    parser.add_argument('-qe', '--end_date', required=False, help='Query end date')
    parser.add_argument('-bt', '--business_trip', required=False, help='Business trip over time', type=float)

    args = parser.parse_args()
    if args.username:
        USERNAME = args.username
    if args.password:
        PASSWORD = args.password
    if args.query_mon:
        QUERY_MON = args.query_mon
    if args.query_year:
        QUERY_YEAR = args.query_year
    if args.business_trip:
        BUSINESS_TRIP = args.business_trip

    # 打印用户名
    print(f'用户名: {USERNAME}')
    print("--------")
    return args


def printStatData(workDayOverHours, holidayOverHours):
    print(f"工作日加班: {workDayOverHours:5.2f}")
    print(f"休息日加班: {holidayOverHours:5.2f}")
    if (BUSINESS_TRIP > 0.0):
        print(f"出差加班:   {BUSINESS_TRIP:5.2f}")

    print(f"总加班时间: {(workDayOverHours + holidayOverHours + BUSINESS_TRIP):5.2f}")
    print("--------")


def getQueryDaysRange(args, year=None, month=None):
    if year:
        year = int(year)
    else:
        year = date.today().year

    if month:
        month = int(month)
    else:
        month = date.today().month

    # 获取当月第一天的星期和当月的总天数
    firstDayWeekDay, monthRange = calendar.monthrange(year, month)

    # 获取当月的第一天
    firstDay = date(year=year, month=month, day=1)
    lastDay = date(year=year, month=month, day=monthRange)

    begin_date = firstDay.strftime('%Y-%m-%d')
    end_date = lastDay.strftime('%Y-%m-%d')

    if args.begin_date:
        begin_date = args.begin_date
    if args.end_date:
        end_date = args.end_date

    print(f"统计日期: {begin_date} ~ {end_date}")
    print("--------")
    return begin_date, end_date


#@pysnooper.snoop("debug.log")
def getLt(aSession):
    firstUrl = "https://portal.supcon.com/cas-web/login?service=https%3A%2F%2Fehr.supcon.com%2FRedseaPlatform%2F"
    responseRes = aSession.get(firstUrl)
    # 无论是否登录成功，状态码一般都是 statusCode = 200
    #print(f"statusCode = {responseRes.status_code}")
    #print(f"text = {responseRes.text}")

    lt_content = responseRes.text
    get_lt_pattern = re.compile(
        r'<input type="hidden" name="lt" value="(.*?)".*/>', re.S | re.M
    )
    _lt = re.findall(get_lt_pattern, lt_content)

    #print(f"lt = {_lt[0]}")
    return _lt[0]


#@pysnooper.snoop("debug.log")
def getStaffId(aSession):
    url = "https://ehr.supcon.com/RedseaPlatform/PtPortal.mc?method=classic"
    responseRes = aSession.get(url)

    #print(f"statusCode = {responseRes.status_code}")
    #print(f"text = {responseRes.text}")

    staffid_content = responseRes.text
    get_staffid_pattern = re.compile(r"staffId: '(.*?)'", re.S | re.M)
    _staffid = re.findall(get_staffid_pattern, staffid_content)

    #print(f"staffId = {_staffid[0]}")
    if len(_staffid) < 1:
        print("用户名或密码错误，请在网站（https://portal.supcon.com）检查脚本所使用的用户名和密码")
        exit()

    return _staffid[0]


#@pysnooper.snoop("debug.log")
def login(aSession, username, password):

    b64password = base64.b64encode(password.encode())

    lt = getLt(aSession)

    postData = {
        "portal_username": username,
        "password": b64password,
        "bakecookie": "on",
        "lt": lt,
        "_eventId": "submit",
        "username": username,
    }

    # JSESSIONID = aSession.cookies.get_dict()["JSESSIONID"]
    # print(f"JSESSIONID = {JSESSIONID}")

    # loginUrl = "https://portal.supcon.com/cas-web/login;jsessionid="+ JSESSIONID + "?service=https%3A%2F%2Fehr.supcon.com%2FRedseaPlatform%2F"
    loginUrl = "https://portal.supcon.com/cas-web/login?service=https%3A%2F%2Fehr.supcon.com%2FRedseaPlatform%2F"
    #print(f"loginUrl = {loginUrl}")

    # 使用session直接post请求
    responseRes = aSession.post(loginUrl, data=postData, headers=header)

    #print(f"statusCode = {responseRes.status_code}")
    #print(f"text = {responseRes.text}")


#@pysnooper.snoop("debug.log")
def getEhrRecords(aSession, staffId, beginDate, endDate):

    postData = {
        "staff_id": staffId,
        "bc_date": beginDate,
        "bc_date_end": endDate
    }

    queryUrl = "https://ehr.supcon.com/RedseaPlatform/getList/kq_data_queryByStaffId/CoreRequest.mc?"
    #print(f"queryUrl = {queryUrl}")

    responseRes = aSession.post(queryUrl, data=postData, headers=header)

    #print(f"statusCode = {responseRes.status_code}")
    #print(f"ehrRecords = {responseRes.text}")

    ehrRecords = json.loads(responseRes.text)

    # [调试]输出records.json
    if 'RECORDS_DUMP_FILE' in globals():
        textFile = open(RECORDS_DUMP_FILE, "w")
        textFile.write(responseRes.text)
        textFile.close()

    # [调试]输入records.json
    if 'RECORDS_DEBUG_FILE' in globals():
        textFile = open(RECORDS_DEBUG_FILE, 'r')
        ehrRecords = json.loads(textFile.read())
        textFile.close()

    return ehrRecords


#@pysnooper.snoop("debug.log")
def getWorkdayInfos(aSession, staffId, beginDate, endDate):

    postData = {
        "staff_id": staffId,
        "begin": beginDate,
        "end": endDate,
        #"fcs_date_year": year,
        #"fcs_date_month": mouth - 1,   # Base 0
    }

    queryUrl = "https://ehr.supcon.com/RedseaPlatform/getList/kq_count_abnormal_SelectStaffID/CoreRequest.mc?"
    #print(f"queryUrl = {queryUrl}")

    responseRes = aSession.post(queryUrl, data=postData, headers=header)

    #print(f"statusCode = {responseRes.status_code}")
    #print(f"workdatInfos = {responseRes.text}")

    workdatInfos = json.loads(responseRes.text)

    # [调试]输出workday_info.json
    if 'WORKDAY_DUMP_FILE' in globals():
        textFile = open(WORKDAY_DUMP_FILE, "w")
        textFile.write(responseRes.text)
        textFile.close()

    # [调试]输入workday_info.json
    if 'WORKDAY_DEBUG_FILE' in globals():
        textFile = open(WORKDAY_DEBUG_FILE, 'r')
        workdatInfos = json.loads(textFile.read())
        textFile.close()

    return workdatInfos


def prepareData(ehrRecords, workdayInfos):
    # 获取所有工作日排班
    allWorkDays = {}
    for aDay in workdayInfos["result"]["#result-set-1"]:
        if not aDay["begin_time"] and not aDay["end_time"]:
            continue

        work_day = aDay["work_day"]
        begin_time = f'{work_day} {aDay["begin_time"]}'
        end_time = f'{work_day} {aDay["end_time"]}'

        # final_state
        # 6:请假 12：加班

        # kq_status_total
        # 0：休息 1：正常

        begin_time_dt = datetime.strptime(begin_time, "%Y-%m-%d %H:%M")
        end_time_dt = datetime.strptime(end_time, "%Y-%m-%d %H:%M")

        allWorkDays[work_day] = [begin_time_dt, end_time_dt]

    allKq = {}
    for aRecord in ehrRecords["jsonList"]:
        bc_date = aRecord["bc_date"]
        allKq[bc_date] = []

    for aRecord in ehrRecords["jsonList"]:
        bc_date = aRecord["bc_date"]

        # status
        # 1：正常上班 3：旷工 5：正常下班 6：工作日无效打卡/休息日正常打卡
        status = aRecord["status"]
        if status and status == "3":
            continue

        # time_order
        # 1：班次1 2：班次2

        # kq_type
        # 2: 安卓？9：刷卡 41：补打卡

        # addr_status
        # 0：正常，1：脱岗

        # create_time
        # 打卡记录创建时间（打卡时间、补打卡时间）

        # operate_time
        # 发起查询时间

        # 跳过脱岗打卡数据
        addr_status = aRecord["addr_status"]
        if addr_status and addr_status != "0":
            continue

        # 跳过无效打卡
        # 4: 周末无效打卡 "": 无效打卡
        kq_bc_id = aRecord["kq_bc_id"]
        if kq_bc_id == "":
            continue

        kq_time = datetime.strptime(aRecord["kq_time"], "%Y-%m-%d %H:%M:%S")
        allKq[bc_date].append(kq_time)

    return allWorkDays, allKq


#@pysnooper.snoop("debug.log")
def statData(allWorkDays, allKq):
    global BUSINESS_TRIP

    workDayOverHours = 0.0
    holidayOverHours = 0.0

    for key, value in allKq.items():
        # 过滤只有一次刷卡的情况
        if len(value) <= 1:
            continue

        bc_date = key
        first_kq = min(value)
        last_kq = max(value)

        if bc_date in allWorkDays:
            # Workday
            begin_time = allWorkDays[bc_date][0]
            end_time = allWorkDays[bc_date][1]

            # if bc_date == '2019-11-15':
            #     tmp = 0

            # 早上首次刷卡与班次开始时间（08:00）之差，用于修正加班开始时间
            fixSeconds = 0
            firstTimeDelta = first_kq - begin_time
            if firstTimeDelta.seconds > 0 and firstTimeDelta.days >= 0:
                fixSeconds = firstTimeDelta.seconds
            
            # 计算加班时，补卡与正常刷卡相同，视为正常
            # 计算加班时，请假开始时间与正常刷卡相同
            # 而请假开始时间由个人填写，这里按8点计算：）
            print_abnormal = False
            if (fixSeconds > 3600):
                print_abnormal = True
                fixSeconds = 0

            # 晚上末次刷卡与班次结束时间之差
            lastTimeDelta = last_kq - end_time
            seconds = (lastTimeDelta.seconds - (30 * 60))

            # 按弹性加班时间，修正加班时间
            seconds = seconds - fixSeconds

            if seconds > 0 and lastTimeDelta.days >= 0:
                seconds = seconds // 60 * 60
                hours = round(seconds/3600, 3)

                # 跳过小于0.5小时的加班时间
                if seconds < 1800:
                    continue

                # 请假开始时间不确定，仍计算加班时间
                #if print_abnormal:
                #    hours = 0

                workDayOverHours = workDayOverHours + hours

                # 打印加班时间
                if (print_abnormal):
                    # 异常加班，打印首末次刷卡
                    first_kq_str = first_kq.strftime("%H:%M:%S")
                    last_kq_str = last_kq.strftime("%H:%M:%S")
                    print(f"{bc_date} [W] {hours:5.2f}" \
                        f" ??? {first_kq_str} ~ {last_kq_str}")
                else:
                    # 正常加班
                    print(f"{bc_date} [W] {hours:5.2f}")
        else:
            # Holiday
            seconds = (last_kq - first_kq).seconds

            if seconds > 0:
                seconds = seconds // 60 * 60           
                hours = round(seconds/3600, 2)
                holidayOverHours = holidayOverHours + hours

                # 打印加班时间
                print(f"{bc_date} [H] {hours:5.2f}")

        # End if
    # End for

    print("--------")
    return workDayOverHours, holidayOverHours


if __name__ == "__main__":
    main()
