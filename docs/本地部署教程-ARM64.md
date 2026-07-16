# DouYinSparkFlow 本地部署教程（ARM64 / Linux 原生）

本教程记录了在 ARM64 Linux 开发板（鲁班猫 / Ubuntu 22.04）上原生部署 DouYinSparkFlow 的完整流程，**只包含经过实测的正确步骤**，可直接照抄。

适用环境：
- 系统架构：`aarch64` / `arm64`（x86_64 同样适用）
- 操作系统：Ubuntu 22.04 / Debian 系
- 内存：≥ 3.8 GB
- 已能联网访问 `creator.douyin.com`

> ⚠️ 不要走 Docker、不要走系统 `chromium-browser` 包、不要走 snap chromium。这三个坑在本项目里都不通，原因见文末「附录：踩过的坑」。

---

## 0. 准备工作

### 0.1 服务器端口放行

如果服务器是经过 frps 端口映射 + 阿里云安全组暴露的，需要先放行 SSH 端口，否则连不上。

### 0.2 拉取代码

```bash
cd ~
git clone https://github.com/12userzhou/DouYinSparkFlow.git douyinsparkflow
# 如果是你自己 fork 的仓库，把 URL 换成 fork 地址
cd douyinsparkflow
```

### 0.3 关闭 GitHub Action 定时（重要）

> ⚠️ 本项目默认带 3 个 GitHub Actions 定时工作流（`schedule.yml` / `schedule_api.yml` / `schedule_dev.yml`），每天都会自动跑一次。既然改用本地 crontab 部署，**必须关掉 GitHub 这边的定时**，否则会：
> - 和本地 crontab 重复发送消息，给好友连发两条
> - GitHub Action 的出口 IP 是境外/共享 IP，容易触发抖音风控导致 cookie 失效

**关键认知**：GitHub Actions 跑在 GitHub 自己的云服务器上，跟你本地设备完全无关。所以关掉它**不需要碰本地代码，不需要 git pull/push**，只要在 GitHub 网页上点一下就行。

#### 方式 A：GitHub UI 禁用（推荐，30 秒搞定）

不需要任何 git 操作，直接在网页上点：

1. 打开 `https://github.com/<你的用户名>/DouYinSparkFlow/actions`
2. 左侧列表依次点这三个 workflow：
   - `DouYin Spark Flow Schedule Run`
   - `【api（测试）分支】DouYin Spark Flow Schedule Run`
   - `【dev（测试）分支】DouYin Spark Flow Schedule Run`
3. 进每个 workflow 后，点右上角 **`...`** → **`Disable workflow`**

禁用后定时和手动触发都会停止，本地 crontab 不受影响。**做完这一步就够了，下面的方式 B 可以跳过。**

#### 方式 B：改 workflow 文件后 push（可选，需带 workflow scope 的 PAT）

如果你想把"已禁用定时"的状态固化进代码仓库（方便别人 clone 下来默认就是关的），可以编辑三个 workflow 文件，把 `schedule:` 触发器注释掉：

```yaml
on:
  workflow_dispatch: # 允许手动触发
  # 已改为本地 crontab 部署，禁用 GitHub Action 定时
  # schedule: # 定时任务
  #   - cron: "0 19 * * *"
```

然后提交并推送：

```bash
git add .github/workflows/
git commit -m "ci: 禁用 GitHub Actions 定时触发"
git push origin main
```

> ⚠️ 注意：push 含 `.github/workflows/` 的改动要求 PAT **带 `workflow` scope**，否则会报 `refusing to allow a Personal Access Token to create or update workflow ... without workflow scope`。去 https://github.com/settings/tokens 勾上 `workflow` scope 重新生成即可。不想折腾 token 的话，直接用方式 A，效果一样。

---

**验证关闭成功**：到 GitHub 仓库 → Actions 页面，确认没有新的自动触发运行记录。本地 crontab 照常每天定点跑。

---

## 1. 一键部署环境

仓库里有现成的 `setup-native.sh`，它会自动完成以下 5 步：

1. 安装系统依赖（Python venv + Playwright 运行库 libnss3 / libatk / libgbm 等）
2. 创建 Python 虚拟环境（用 `--without-pip` + `get-pip.py` 兜底，绕开 Ubuntu 22.04 上 venv 不完整的问题）
3. 用阿里云镜像装 Python 依赖
4. 用 Playwright 官方 CDN 下载 arm64 chromium headless_shell
5. 创建 logs 目录

直接执行：

```bash
bash setup-native.sh
```

> 关键点：
> - chromium 必须用 `PLAYWRIGHT_DOWNLOAD_HOST=https://playwright.azureedge.net` 走官方 CDN，国内 npmmirror 镜像缺 arm64 headless_shell 包会 404。
> - venv 必须用 `--without-pip`，否则在部分 Ubuntu 22.04 上 venv 创建不完整（只有 python 软链，没有 activate / pip）。
> - 不要装系统的 `chromium-browser` 包，它在 arm64 上是个 wrapper 脚本会报错，而且 snap 版本受 GLIBC 限制跑不起来。

部署成功后，会看到类似输出：

```
==========================================
  部署完成！
==========================================
```

---

## 2. 创建 .env 配置文件

在项目根目录创建 `.env`，模板可参考 `.env.example`。下面是一份**实测可用**的最小配置示例：

```dotenv
# ===== 普通变量 =====
# 消息内容（不需要一言就直接写文字）
MESSAGE_TEMPLATE=早上好

# 一言类型（MESSAGE_TEMPLATE 不含 [API] 时这个字段会被忽略）
HITOKOTO_TYPES=["文学","影视","诗词","哲学"]

# 匹配模式：short_id = 按抖音号匹配（推荐，比 nickname 稳定）
MATCH_MODE=short_id

BROWSER_TIMEOUT=120000
FRIEND_LIST_WAIT_TIME=2000
TASK_RETRY_TIMES=3
LOG_LEVEL=INFO

# ===== 任务列表 =====
# username 是备注名（日志里用）；unique_id 用于关联下面的 COOKIES_<UNIQUE_ID 大写>
# targets 里填好友的【抖音号 unique_id】或【纯数字 short_id】，两种都能匹配
TASKS=[{"username":"你的账号备注名","unique_id":"u1","targets":["好友抖音号1","好友抖音号2"]}]

# ===== Cookie =====
# 从浏览器开发者工具导出的 Cookie JSON 数组（数组里每个对象要有 name/value/domain/path）
COOKIES_U1=[{"name":"sessionid","value":"替换成真实值","domain":".douyin.com","path":"/"}, ...]
```

### 2.1 怎么获取 targets（好友抖音号）

在抖音 APP 里点开好友主页 → 右上角分享 → 复制链接，链接里的 `u/` 后面那段就是抖音号。
也可以让对方报给你，或者看对方主页的「抖音号：xxx」一栏。

> ⚠️ 抖音号末尾如果有英文句号 `.`，**必须保留**（比如某些抖音号是 `xxx.` 结尾），否则匹配不上。

### 2.2 怎么导出 Cookie

1. 用电脑浏览器（推荐 Chrome）打开 https://creator.douyin.com/ 并登录
2. 按 F12 打开开发者工具 → Network 面板 → 刷新页面
3. 随便点一个请求 → Headers → Cookie 字段，把整串 Cookie 复制
4. 用浏览器插件（如 EditThisCookie / Cookie-Editor）一键导出 JSON 数组格式
5. 把整个 JSON 数组粘贴到 `.env` 的 `COOKIES_U1=` 后面

> Cookie 有效期大约 1~4 周，过期后会出现「检测到登录/扫码页面，cookie 可能已失效」，按本文档「4. 后续维护」一节更新即可。

---

## 3. 手动运行验证

```bash
cd ~/douyinsparkflow
source venv/bin/activate
python -u main.py 2>&1 | tee /tmp/run.log
```

看到这样的日志说明发送成功：

```
[browser] 使用 Playwright headless_shell: /home/<用户名>/.cache/ms-playwright/chromium_headless_shell-<版本号>/chrome-linux/headless_shell
INFO - 开始执行任务
INFO - 开始处理账号 你的账号备注名
INFO - 监听到 user_detail 接口响应，user_list 共 N 条
INFO - 选中目标好友 好友昵称 (好友抖音号) 准备开始交互
INFO - 已选中好友 好友昵称，准备发送消息
INFO - 准备输入消息给好友 好友昵称：'早上好'
INFO - 输入框实际内容：'早上好'
INFO - 给好友 好友昵称 发送消息完成（输入框已清空）
...
INFO - 任务完成
```

每个好友都会经历「选中 → 输入 → 验证输入框内容 → 回车发送 → 清空确认」五个步骤。

---

## 4. 后续维护

### 4.1 设置每天 4 点定时执行

```bash
# 编辑 crontab
crontab -e
```

加入下面这行（注意把路径换成你的真实路径）：

```cron
0 4 * * * cd /home/<用户名>/douyinsparkflow && /home/<用户名>/douyinsparkflow/venv/bin/python main.py >> /home/<用户名>/douyinsparkflow/logs/cron.log 2>&1
```

保存退出。验证：

```bash
crontab -l
```

### 4.2 更新 Cookie（最常用的维护操作）

Cookie 过期后，重新从浏览器导出，然后二选一：

**方式 A：用脚本（推荐）**

```bash
cd ~/douyinsparkflow
bash update_cookie.sh
# 把新 cookie JSON 粘进去，Ctrl+D 结束
```

如果是多账号，第一个参数填 `UNIQUE_ID` 大写：

```bash
bash update_cookie.sh U1
```

脚本会自动备份原 `.env` 为 `.env.bak`，然后用 Python 安全替换（避免 sed 处理特殊字符出错）。

**方式 B：手动编辑**

```bash
nano ~/douyinsparkflow/.env
# 找到 COOKIES_U1= 那一行，整行替换
```

更新后立即跑一次验证：

```bash
source venv/bin/activate && python -u main.py 2>&1 | tee /tmp/run.log
```

### 4.3 改消息内容

```bash
cd ~/douyinsparkflow
# 例如改成"晚安"
sed -i 's|^MESSAGE_TEMPLATE=.*|MESSAGE_TEMPLATE=晚安|' .env
```

### 4.4 改好友列表

```bash
cd ~/douyinsparkflow
# 整行替换 TASKS=
# 注意 targets 里的抖音号结尾如果有 . 必须保留
sed -i 's|^TASKS=.*|TASKS=[{"username":"你的账号备注名","unique_id":"u1","targets":["好友抖音号1","好友抖音号2"]}]|' .env
```

### 4.5 查看日志

```bash
# crontab 的运行日志
tail -f ~/douyinsparkflow/logs/cron.log

# 旧的运行日志（每次手动运行会覆盖）
ls ~/douyinsparkflow/logs/
```

### 4.6 判断 Cookie 是否过期

跑一次 `python -u main.py`，如果日志里反复出现：

```
ERROR - 账号 xxx 第 1/3 次检测到登录/扫码页面，cookie 可能已失效
ERROR - 账号 xxx 第 2/3 次检测到登录/扫码页面，cookie 可能已失效
ERROR - 账号 xxx 第 3/3 次检测到登录/扫码页面，cookie 可能已失效
```

就是 Cookie 过期了，按 4.2 节更新即可。

---

## 5. 常见问题

### Q1：`ModuleNotFoundError: No module named 'dotenv'`

没有激活 venv，或者 venv 没装好。

```bash
cd ~/douyinsparkflow
source venv/bin/activate
python -u main.py
```

### Q2：`chromium-headless-shell-linux-arm64.zip 404`

下载源不对，必须用官方 CDN：

```bash
source venv/bin/activate
PLAYWRIGHT_DOWNLOAD_HOST=https://playwright.azureedge.net playwright install chromium
```

### Q3：`Missing X server`

启用了完整 chromium 而不是 headless_shell。项目 `core/browser.py` 已经做了自动选择，确保 `~/.cache/ms-playwright/chromium_headless_shell-*/` 目录存在即可。

### Q4：`requires the chromium snap to be installed`

误用了系统 chromium。卸载 snap chromium：

```bash
sudo snap remove chromium
```

然后让程序用 Playwright 自带的 headless_shell。

### Q5：只给第一个好友发了消息

检查 `.env` 里 `TASKS` 的 `targets` 数组是不是真的有多个元素，以及抖音号结尾的 `.` 有没有漏掉。

### Q6：日志里出现 `解析响应失败: Response.json: Target page, context or browser has been closed`

无害噪音，浏览器关闭时残留接口响应触发的，已经做了静默处理，可以忽略。

### Q7：crontab 不执行

1. 确认 crond 服务在跑：`sudo systemctl status cron`
2. 确认 venv 路径对：`ls /home/<用户名>/douyinsparkflow/venv/bin/python`
3. 看日志：`tail -f /home/<用户名>/douyinsparkflow/logs/cron.log`

### Q8：GitHub Action 还在定时跑，和本地 crontab 重复发送

说明 workflow 没被禁用。最快的解决办法是去 GitHub UI 直接禁用（不需要 git 操作），见本文档「0.3 关闭 GitHub Action 定时 → 方式 A」。

如果走方式 B（改 workflow 文件 push），push 时报 `refusing to allow a Personal Access Token to create or update workflow ... without workflow scope`，说明你的 PAT 没 `workflow` scope，去 token 设置页勾上重新生成就行；不想折腾 token 的话直接用方式 A，效果一样。

---

## 附录：踩过的坑（仅供避雷，无需操作）

| 方案 | 失败原因 |
|---|---|
| Docker 部署 | Playwright 官方 chromium 无 arm64 预编译镜像，Docker build 在 arm64 上卡死 |
| 系统装 `chromium-browser` apt 包 | Ubuntu 22.04 上是个 wrapper 脚本，会报 `requires the chromium snap to be installed` |
| snap chromium | 1) 鲁班猫受限内核报 `cannot attach cgroup`；2) 真实二进制报 `GLIBC_2.38 not found`（Ubuntu 22.04 只有 2.35）|
| npmmirror 下载 Playwright chromium | 缺 arm64 headless_shell 包，404 |
| `python3 -m venv venv` 不带参数 | Ubuntu 22.04 上 venv 创建不完整（只有 python 软链，没有 activate / pip） |
| 用完整 chromium 跑 headless | 报 `Missing X server`，必须用 headless_shell |

最终的正确方案就是本教程第 1 节的 `setup-native.sh`：**Playwright 官方 CDN 下载 arm64 headless_shell + `--without-pip` 创建 venv**。
