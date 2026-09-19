import logging
import os
from logging.handlers import RotatingFileHandler

# 创建 logs 文件夹（如果不存在）
if not os.path.exists("logs"):
    os.makedirs("logs")

# 日志格式
LOG_FORMAT = "%(asctime)s - %(name)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s"

# 日志文件路径
LOG_FILE = "logs/app.log"

# 配置日志
def setup_logger(name="app", level="Info"):
    """
    配置日志记录器
    :param name: 日志记录器名称
    :param level: 日志级别
    :return: 配置好的日志记录器
    """
    # 大小写不敏感，兼容 "DEBUG" / "Debug" / "debug" 等写法
    _level_map = {
        "debug": logging.DEBUG,
        "info": logging.INFO,
        "warning": logging.WARNING,
        "error": logging.ERROR,
    }
    level = _level_map.get(str(level).lower(), logging.INFO)
    
    logger = logging.getLogger(name)
    logger.setLevel(level)

    # 防止重复添加处理器
    if not logger.handlers:
        # 控制台日志处理器
        console_handler = logging.StreamHandler()
        console_formatter = logging.Formatter(LOG_FORMAT)
        console_handler.setFormatter(console_formatter)

        # 文件日志处理器（带日志轮转）
        file_handler = RotatingFileHandler(LOG_FILE, maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8")
        file_formatter = logging.Formatter(LOG_FORMAT)
        file_handler.setFormatter(file_formatter)

        # 添加处理器到日志记录器
        logger.addHandler(console_handler)
        logger.addHandler(file_handler)

    # [修复] 每次 setup_logger 被调用时都同步更新所有 handler 的级别，
    # 否则被 config.py 提前初始化后，tasks.py 想把级别调成 DEBUG 也不生效，
    # 导致 DEBUG 级日志（如 "接口返回好友"）被 INFO handler 过滤掉
    for h in logger.handlers:
        h.setLevel(level)

    return logger


# 示例：使用日志记录器
if __name__ == "__main__":
    logger = setup_logger(level="Debug")
    logger.debug("这是一个调试信息")
    logger.info("这是一个普通信息")
    logger.warning("这是一个警告信息")
    logger.error("这是一个错误信息")
    logger.critical("这是一个严重错误信息")