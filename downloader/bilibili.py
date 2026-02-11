import requests
import json

headers = {
    'User-Agent': '''Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0''',
    'Cookie': '''buvid3=D84082E0-2826-97AA-44E0-4ED255D9E6E665697infoc; b_nut=1765646165; _uuid=4FCF9C6F-DFAA-FAD6-E75B-FAE7142B656C65232infoc; buvid4=0FC4AADA-3CC1-B506-31CB-01B4E88A57CA16633-023051716-OkxRG+fwAT6DnGJ7X8oEdUw5LhhUkQXth6V2MwL1H4rMzjB1AEC3cQ%3D%3D; buvid_fp=42a33d40bd861841bdef7ec315d39cee; theme-tip-show=SHOWED; rpdid=|(k|mYuJJ|lm0J'u~YlYY~uRk; theme-avatar-tip-show=SHOWED; DedeUserID=166296319; DedeUserID__ckMd5=c6473c946674aaf5; theme-switch-show=SHOWED; CURRENT_QUALITY=120; LIVE_BUVID=AUTO8917692607557512; ogv_device_support_hdr=1; hit-dyn-v2=1; PVID=2; bili_ticket=eyJhbGciOiJIUzI1NiIsImtpZCI6InMwMyIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NzA2NDI5MTMsImlhdCI6MTc3MDM4MzY1MywicGx0IjotMX0.s22tl8p9WUWmi_leNxPY8Q6IcZL5MyjJG1vdpqqc638; bili_ticket_expires=1770642853; SESSDATA=0b54db80%2C1785958948%2C3f712%2A21CjDaRL8c4nKEJbM6tFPufC8lpyfn-xTxMFpzV50G42RkUBQW3_BgUK2p4Dv0Sl803N8SVkdLeGJSMWQ4ZWxVbWZwU2RjaXpLWDJHaVBhdjZJNnFqb1VmNkZxdTZRbjI4TFBKX05IbVBucnNkRzN2ZUlsbURZVTQ3clR1eS0xVGo0bklVVlZFdVBnIIEC; bili_jct=0d2128a43d282e3c4e1eb2813ac24f6b; sid=8mg4whho; CURRENT_FNVAL=4048; bp_t_offset_166296319=1166626642169167872; browser_resolution=1141-669; home_feed_column=4; b_lsid=6CEF47E6_19C38FFDEFF''',
    'Referer': '''https://space.bilibili.com/166296319/favlist?fid=1003383619&ftype=create&spm_id_from=333.1007.0.0'''
}

response = requests.get(
    url='''https://api.bilibili.com/x/v3/fav/resource/list?media_id=1003383619&pn=3&ps=40&keyword=&order=mtime&type=0&tid=0&platform=web&web_location=333.1387''',
    headers=headers)


a = json.loads(response.text)['data']['medias']
