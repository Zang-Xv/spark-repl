# 用来流式记录我遇到的问题

大概是随手记下我遇到的问题和我的解决方法

## 复现和毕设过程中必要的问题

模型下载难如登天
勉强通过镜像等等完成

浏览器疯狂提示跨域问题
系统补充了前后端通信和跨域的知识, 最后发现是后端接口爆了导致的问题

/setting1 莫名调用utils.py来进行文件清理, 但是我并没有这个路径导致报错
添加了一个 path.ok 的检测, 如果不存在就跳过, 等待后面输出的时候创建

我发现还有很多路径问题, 都是检测不到路径导致的报错
先直接添加对应的路径以便快速跑起来, 然后项目的可迁移性调整后续再慢慢修改
我已经直接把output文件夹真个加入gitignore里面了, 我想其实最好的做法应该是把这些文件夹在首次运行的时候就直接创建出来?

```py
# 路径记录
'/output/preview/'
'/output/mask/bar/background/mask_reverse.png', "output/mask/bar/foreground",
"output/mask/line/background", "output/mask/line/foreground",
"output/mask/pie/background", "output/mask/pie/foreground"
```

又有路径设置问题, 看来项目里面应该还会出现很多次
这毕竟是一个学习研究向的项目, 没有那种用户性质的设置
我先使用搜索功能统一进行替换`/home/ubuntu/ChartSpark`
**todo**: 整理一个可以获取当前目录的方法, 或者使用相对路径, 或者学习更加工程的做法
```bash
  File "/home/ubuntu/ChartSpark/mask/bar_mask.py", line 37, in table2img_bar
    fig.savefig('/home/ubuntu/ChartSpark/frontend/src/assets/preview/bar_preview.png', dpi=fig.dpi)
  line 44
    fig.savefig("/home/ubuntu/ChartSpark/frontend/src/assets/preview/plot.svg", transparent = True, format="svg", dpi=fig.dpi)
  line 46
    return '/home/ubuntu/ChartSpark/frontend/src/assets/preview/bar_preview.png'
```

在使用的时候常常系统界面一点反应都没有, 也不知道出了什么问题, 只能一点一点排查, 并不是很易用
**todo**: 添加一些关于setting1接口500 的弹窗提示, 在setting1正在加载pending的时候增加一个弹窗显示状态

怎么又要加载一个'all-mpnet-base-v2'的模型? 这是在干什么?
这个模型似乎是用来提取关键字的, 姑且就先直接缓存下来吧
```bash
  File "/home/ubuntu/ChartSpark/theme_extract/similar_text.py", line 38, in extract_kw_similar
    kw_model = KeyBERT(model='all-mpnet-base-v2')
```

怎么还有命名错误的
bg_removel.pth -> bg_removal.pth, 名称修正
```bash
  File "/home/ubuntu/ChartSpark/mask/bg_removal.py", line 627, in bg_removal
    model_path = os.path.join(current_path, 'mask', 'bg_removel.pth')  # the model path
```

发现显存又爆了,24G显存都不够?
似乎是你现在这个现象非常典型：父进程 + 子进程，子进程会重新 import 你的主模块，而你把 4 个 diffusion pipeline 都在模块顶层加载到 CUDA 了，所以每个进程都会各自把模型搬上 GPU → 显存被“重复占用”。
最稳的修复：不要在模块顶层加载 GPU 模型，改成“惰性加载（只在真正服务进程里加载一次）”
**todo**: 改为懒加载模式
改了reload之后似乎就不会再呼出子进程了?
但是装载的时候总是提示缺少模型xx, 还是需要调整

## 胡思乱想

服务器配置没整明白
学习了各种服务器功能并整理了文档

跨域没整明白
补充了前后端通信的知识, 并整理了文档

代码中怎么try catch, 怎么抛出异常并处理错误没整明白