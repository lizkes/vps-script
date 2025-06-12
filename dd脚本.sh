bash <(curl -skL "https://github.000060000.xyz/tcp.sh")

#https://github.com/leitbogioro/Tools?tab=readme-ov-file#parameters-detail-descriptions
#默认用户名 root
#默认密码 LeitboGi0ro
wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh
bash InstallNET.sh -debian 12
#重装windows系统
#镜像地址 https://dl.lamp.sh/vhd/
#默认用户名 Administrator
#默认密码 Teddysun.com
wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh
bash InstallNET.sh -lang "cn" -dd "https://dl.lamp.sh/vhd/zh-cn_windows10_ltsc.xz" -partition "gpt" --ip-addr "31.56.123.118" --ip-gate "31.56.123.1" --ip-mask "24" --ip6-addr "2401:1da0::1e3" --ip6-gate "2401:1da0::1" --ip6-mask "64" --networkstack "dual"
