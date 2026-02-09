# readme fix

用于记录一些我发现的问题以及上手项目需要修改的地方
虽然其实这些都有 bug 提示
但是能够记录下来的话也可以防止其他人走老路, 可以更快上手并复现
说不定发给作者还能混个项目维护者的名头:P

## 前期配置

### 服务运行端口

感觉这个属于个人配置, 似乎不太好补充到 md 里面?

如果不想运行在原来的端口, 或者使用服务器的时候默认端口的权限不足
需要修改:
```bash
File "/ChartSpark/chartSpeak.py", line 303, in app.run
    app.run(host='127.0.0.1', port=88, debug=True)
File "/ChartSpark/frontend/src/service/dataService.js", line 3
    const T_URL = 'http://127.0.0.1:88';
File "/ChartSpark/frontend/vite.config.js", line 10, in defineConfig
    port: 8080,
```

### 文件路径

有一些文件调用路径是绝对路径, 需要修改成为自己的路径

```bash
File "/ChartSpark/utils.py", line 8, in clear_folder
    main_folder = "/home/ubuntu/ChartSpark/"
```

### 一些bug和易用性调整

关于目录不存在导致接口500, 可以直接跳过目录删除
```bash
File "/home/ubuntu/ChartSpark/utils.py", line 19, in clear_folder
    for filename in os.listdir(main_folder+folder_path[i]):
FileNotFoundError: [Errno 2] No such file or directory: '/home/ubuntu/ChartSpark/output/mask/bar/background'
```
