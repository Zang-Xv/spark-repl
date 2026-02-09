## ChartSpark pipeline 学习指南（从 0 到能回答“数据/Prompt/条件如何流动”）

这份笔记的目标：让你能逐层回答四类问题：

1) 系统整体：ChartSpark 的 pipeline 是怎样的？数据 / prompt / 条件如何流动？
2) 生成逻辑：prompt 在哪一层构造？风格/语义/结构条件在哪里注入？diffusers pipeline 如何初始化与调用？
3) 模块职责：哪些必须理解（白盒）？哪些可以暂时当黑盒？前后端边界在哪里？
4) 可控性：你现在能控制什么？不能控制什么？哪里最适合做“研究变量”？

下面按“先跑通 → 再读调用链 → 再拆 prompt/条件 → 再整理可控变量”的节奏推进。

---

## 0. 先建立心智模型（你要记住的 4 个名词）

### 0.1 两个阶段：Preview vs Generate

- Preview（预览阶段）：把数据（JSON）渲染成“普通图表”，并生成结构条件（mask），以及主题词云。
	- 后端入口：/setting1
	- 关键产物：预览图 + 前景/背景 mask 路径
- Generate（生成阶段）：把 prompt + 结构条件（可选）喂给扩散模型，生成“图表中的语义元素（前景）”或“图表背景”。
	- 后端入口：/generate_element
	- 关键产物：一组 PIL 图 → base64 dataURI 返回前端

---
pil图是什么? 为什么这里使用base64的uri?
前景/背景mask路径有什么用?
setting1在后端只是返回了图片路径, 这在前端要怎么调用并传输到另一个服务器上啊
前后端通信当中的数据传输链路是怎么样的? 图象这种数据怎么办? 是什么类型的 content-type啊?
我单独看一个后端接口其实很难知道到底这里有什么? 只有一个request.get_json()我完全不知道有什么数据啊? 如果是生产中的前后端要怎么协作完成这里? 看接口文档?
如果我想要单独对后端进行单元测试, 我应该怎么做? 模拟一个请求发送? 直接给一个数据? 搞不懂啊
我想要给前端加上一些提示信息来让状态更明显, 可是大部分时候是不是应该要做得更无感才能让用户感受不到应用中的问题呢?

### 0.2 两条生成主线：Foreground vs Background

- F：生成前景元素（例如条形/折线附近的图形元素），常见做法是“生成→抠图→贴回”。
- B：生成背景（图表背后的纹理/图像），常见做法是“先生成底图→与 mask 融合→img2img 细化”。

### 0.3 两种“是否用条件”：UNC vs C

在后端接口里有一个 location（注意：代码里叫 location，不是论文术语）：

- UNC：不使用结构条件（不使用 mask 作为约束输入），本质接近纯 text2img，再做一些后处理。
- C：使用结构条件（mask），把 mask 当成“结构约束”输入到后处理/融合/辅助器（assistant）里。

### 0.4 你真正要追的三股流

- 数据流：前端 JSON → 后端解析 → 画普通图表 → 产出 mask → 前端拿到 mask path → 再把 mask path 传回后端做生成
- Prompt 流：前端 object/description → 后端拼 prompt → 传给 diffusers（text2img / img2img / depth2img / paint-by-example）
- 条件流：mask 图片（foreground/background）→ 作为结构条件注入生成

---

## 1. 系统整体层面：数据 / prompt / 条件 如何流动

这一部分建议你按“请求-响应”读代码，而不是按文件夹读。

### 1.1 前端 → 后端（Preview）

1) 前端导入 JSON：
	 - 文件：../frontend/src/components/importJSON.vue
	 - 行为：读取本地 JSON 文件内容并保存到 Pinia store（store.jsonData）

2) 前端点击 Preview：
	 - 文件：../frontend/src/components/settings.vue
	 - 行为：组装 param（chart-type / aspect-ratio / bar_width / data 等）

3) 前端调用后端：
	 - 文件：../frontend/src/service/dataService.js
	 - 接口：POST http://127.0.0.1:8888/setting1

4) 后端处理：
	 - 文件：../chartSpeak.py
	 - 路由：setting_preview_wc() 处理 /setting1
	 - 做了什么：
		 - json.loads(chart_data) 得到 x/y/title（scatter 还会有 z）
		 - 根据 chart_type 调用 mask/* 里的 table2img_* 与 img2mask_* 生成：
			 - 预览图 output/preview/*.png
			 - mask output/mask/** 以及 frontend/src/assets/mask/**
		 - 调用 theme_extract 提取关键词并生成词云

5) 后端返回给前端：
	 - 返回一个 list： [preview_img_path, wordcloud_path, mask_foreground_path, mask_background_path]
	 - 前端保存 mask 路径（用于下一步 Generate 时传回后端）

你可以用下面的问题自检：

- Q1：mask_path_foreground / mask_path_background 是“文件路径字符串”，还是“图片内容”？
	- 答：目前返回的是路径字符串，真正的图片是保存在磁盘（output/ 与 frontend/src/assets/）

### 1.2 前端 → 后端（Generate）

1) 前端发起生成请求：
	 - 文件：../frontend/src/service/dataService.js
	 - 接口：POST http://127.0.0.1:8888/generate_element

2) 后端核心入口：
	 - 文件：../chartSpeak.py
	 - 路由：generate_element() 处理 /generate_element

3) 后端把输入拆成三类：

- prompt 相关：
	- object_info = data["object"]
	- description = data["description"]
	- prompt = object_info + ", " + description

- 图表类型相关：
	- chart_bool_list = data["chart_type"]
	- chart_type = ["bar","line","pie","scatter"][chart_bool_list.index(True)]（若全 None 默认 line）

- 条件相关（仅当 location == "C"）：
	- mask_path = data["mask"].replace("src/assets", "output")
	- mask_pil = Image.open(mask_path)

4) 后端选择生成分支：

- method_to_generate == "B" and location == "UNC"
	- 调用 generation/UNC.py 的 text2img()（实际上是 pipe_text2img）

- method_to_generate == "F" and location == "UNC"
	- 先 text2img 出候选图
	- 再 extract_element() 抠出前景元素（本质：bg_removal + crop）

- method_to_generate == "F" and location == "C"
	- 根据 chart_type 调用 generation/COND_F.py 的 *Assistant 类
	- 把 mask_pil 作为结构条件喂给 Assistant

- method_to_generate == "B" and location == "C"
	- 根据 chart_type 调用 generation/COND_B.py 的 *Assistant_B 类
	- 把 mask_pil 作为结构条件参与融合/细化

5) 后端输出：

- 如果返回的是 PIL Image list：会被 pil_to_data_uri() 编码成 base64 dataURI 列表返回前端

---

## 2. 生成逻辑层面：Prompt/风格/语义/结构条件分别在哪注入？

### 2.1 Prompt 在哪一层被构造？

- Prompt 构造点：../chartSpeak.py 的 generate_element()
	- prompt = object_info + ", " + description
	- refine_element() 里还有一个 img2img 的 prompt = object_info + description（少了逗号，这是一个潜在不一致点）

理解建议：把 prompt 看成“语义/风格”承载体；把 mask 看成“结构/布局”承载体。

### 2.2 风格 / 语义 / 结构条件分别在哪里注入？

把输入拆开看：

1) 语义（What）：主要在 object_info / description
	 - 你可以在前端输入 “object=cat, description=watercolor style ...” 来直接控制语义/风格

2) 风格（How）：目前主要也靠 prompt 文本（description）
	 - 代码里还有一个固定 negative_prompt（在 generation/COND_F.py 与 COND_B.py 的 depth2img() 里）
	 - 所以风格控制目前分两层：显式 prompt + 固定 negative prompt

3) 结构条件（Where）：来自 mask
	 - mask 的生成：mask/*.py（比如 bar_mask.py、line_mask.py）
	 - mask 的注入：/generate_element 分支 location == "C" 时，传入 Assistant
	 - Assistant 内部会把 mask 用于：
		 - 融合/裁剪/贴回（典型前景流程）
		 - 与背景图 blend 后做 img2img（典型背景流程）

一句话总结：

- Prompt 负责“内容与风格”，mask 负责“结构与布局”，Assistant 负责“把两者对齐并落到图表结构上”。

### 2.3 diffusers pipeline 如何初始化和调用？

初始化位置：../chartSpeak.py 顶部全局加载（导入时执行）。

- pipe_text2img = StableDiffusionPipeline.from_pretrained(...).to("cuda")
- pipe_depth = StableDiffusionDepth2ImgPipeline.from_pretrained(...).to("cuda")
- pipe_img2img = StableDiffusionImg2ImgPipeline.from_pretrained(...).to("cuda")
- pipe_paint = DiffusionPipeline.from_pretrained(...).to("cuda")  （Paint-by-Example）

调用位置（按功能分）：

- 纯 text2img：generation/UNC.py:text2img() 或 generation/COND_F.py:text2img()
- depth2img（带结构图作为 image 输入）：generation/COND_F.py:depth2img() / generation/COND_B.py:depth2img()
- img2img（细化/融合后再生成）：generation/COND_F.py:img2img() / generation/COND_B.py:img2img() 以及 ../chartSpeak.py:refine_element()
- paint-by-example：generation/COND_F.py:paint2img() / generation/COND_B.py:paint2img()

你可以用这三个问题自检：

- Q1：后端有没有“每次请求都重新加载模型”？
	- 答：没有。模型在 chartSpeak.py import 时就加载为全局变量。
- Q2：结构条件到底有没有用到 pipe_depth？
	- 答：部分 Assistant 里 depth2img 逻辑存在，但有的路径改成了直接 text2img（例如 BarAssistant 的单柱情况），所以要以实际调用为准。
- Q3：随机性从哪里来？
	- 答：多处用 torch.Generator(device="cuda").manual_seed(random.randint(...))，即每次随机 seed。

---

## 3. 模块职责层面：白盒 vs 黑盒（以及前后端边界）

### 3.1 必须理解的“白盒模块”（建议按顺序读）

1) ../chartSpeak.py
	 - 为什么：它是后端真实入口，决定了“哪个模块何时被调用”，也决定了参数怎么流动。

2) ../frontend/src/service/dataService.js + ../frontend/src/components/settings.vue
	 - 为什么：它们定义了前端实际向后端发什么字段（也决定了你能控制什么变量）。

3) ../mask/*.py（至少读与你图表类型对应的一个）
	 - 为什么：结构条件（mask）就是论文里“结构约束”的具体落地。
	 - 建议优先：mask/bar_mask.py 与 mask/line_mask.py

4) ../generation/UNC.py
	 - 为什么：它是最简单 baseline：text2img + 抠图（帮助你对照理解“条件化”到底增加了什么）。

5) ../generation/COND_F.py 与 ../generation/COND_B.py
	 - 为什么：这里是“把结构条件用起来”的核心工程实现（Assistant 体系）。

### 3.2 可以暂时当“黑盒”的模块（先会用，再慢慢拆）

- ../mask/bg_removal.py
	- 本质：一个抠图/去背景网络（深度学习模型 + 推理流程）
	- 学习策略：先把它当成一个函数 bg_removal(image)->RGBA

- ../grid/*
	- 本质：一些几何/拼贴/相似度计算工具，用于把元素对齐到网格/条形结构

- ../theme_extract/*
	- 本质：从标题里提关键词并生成词云（更多是工程附加能力）

- ../evaluation/*
	- 本质：评估前景生成质量的一些指标

### 3.3 前端和后端的边界在哪里？

- 前端负责：
	- 收集输入（JSON 数据、图表类型、用户文本 object/description、选择哪张 mask）
	- 展示输出（预览图、mask 预览、生成结果图）
	- 把“mask 的路径字符串”传回后端

- 后端负责：
	- 根据数据生成图表预览与 mask 文件
	- 初始化与调用 diffusers pipeline
	- 生成、抠图、融合、编码为 base64 返回

---

## 4. 可控性层面：你能控制什么？不能控制什么？研究变量放哪最好？

### 4.1 你现在“明确可控”的变量（无需改代码）

- prompt 相关：
	- object（对象/主体词）
	- description（风格、材质、时代、色彩、艺术流派……）

- 结构条件相关：
	- chart-type（bar/line/pie/scatter）
	- aspect-ratio / bar_width / y_min/y_max（影响 mask 形态与图表布局）
	- 选择 foreground mask 还是 background mask（前端保存的 mask_path_foreground/background）

- 生成策略相关：
	- method_to_generate：F 或 B
	- location：UNC 或 C
	- num_to_generate

### 4.2 你目前“不太可控/不可控”的变量

- 扩散模型内部表示（latent、cross-attention 分布、特征图等）：默认不可控
- 随机种子：代码中每次随机生成 seed（因此结果不可复现）
- 关键超参（strength / guidance_scale / negative_prompt）
	- 这些在代码里写死在多个位置（例如 7.5、0.65、0.85 等）

### 4.3 最适合未来做“研究变量”的位置（强烈建议从这里动手）

建议按“改动成本低 → 研究意义高”排序：

1) Prompt 模板化（研究：prompt 构造策略）
	 - 位置：../chartSpeak.py 的 prompt = object + ", " + description
	 - 方向：把 object/description 拆成结构化字段（主体/场景/材质/色彩/风格/禁用词），再拼模板

2) 可复现性（研究：控制随机性）
	 - 位置：generation/COND_*.py 多处 manual_seed(random.randint(...))
	 - 方向：把 seed 从前端传入后端；或在后端统一生成并回传给前端记录

3) 结构条件强度（研究：结构约束 vs 创造性权衡）
	 - 位置：img2img 的 strength、depth2img 的 strength、blend 的 alpha
	 - 方向：把这些参数暴露成可调控滑条

4) mask 预处理（研究：结构条件的形态学与鲁棒性）
	 - 位置：generation/COND_*.py 的 augment_module(mask_pil)
	 - 方向：可控地做 blur/dilate/erode/offset，观察结构遵循程度

5) 前景/背景融合策略（研究：合成策略）
	 - 位置：generation/COND_B.py 的 Image.blend / crop_and_blend
	 - 方向：替换为 Poisson blending、alpha matte、或边界一致性约束

---

## 5. 建议的“逐步学习路线”（每一步 10~30 分钟）

### Step A：跑通一次完整链路（只看输入/输出）

目标：你能说清“前端发了什么 → 后端回了什么 → 文件落在哪里”。

检查点：

- Preview 后你的磁盘里应该出现 output/preview/* 与 output/mask/**
- Generate 后前端收到的是 base64 dataURI 列表（不是文件路径）

### Step B：读 /setting1（理解“数据 → mask”）

阅读顺序：

1) ../chartSpeak.py:setting_preview_wc()
2) ../mask/bar_mask.py 或 ../mask/line_mask.py

检查题：

- 为什么同一个 chart_type 会生成 foreground/background 两类 mask？
- bar 的 mask 为什么既有 mask_all.png 又有 mask_0.png/mask_1.png…？

### Step C：读 /generate_element（理解“prompt + 条件 → 图像”）

阅读顺序：

1) ../chartSpeak.py:generate_element()
2) ../generation/UNC.py
3) ../generation/COND_F.py（至少读 BarAssistant 的 __call__）
4) ../generation/COND_B.py（至少读 BarAssistant_B 的 __call__）

检查题：

- UNC 与 C 的差别到底在哪一行体现？
- 前景生成里“抠图”是哪一步？为什么需要抠图？
- 背景生成里为什么要 blend mask 再 img2img？

### Step D：把“可控变量”做成你的实验面板（开始研究）

最小可做：只改后端，不动前端 UI：

- 在 /generate_element 的输入里临时加入可选字段（seed / guidance_scale / strength），先从 Postman/前端调用改起
- 或者先把这些参数硬编码成一处常量（便于统一管理），避免散落在多文件

---

## 6. 一页总结（你应该能复述出来的版本）

ChartSpark 的真实 pipeline 是：

1) 前端上传/导入数据（JSON），选择图表类型与比例
2) 后端用 matplotlib 画普通图表，并从图表几何结构生成 mask（前景/背景）
3) 前端选择要生成的目标（前景元素 or 背景）与文本（object/description）
4) 后端拼 prompt，并按 UNC/C 分支决定是否注入 mask 条件
5) 后端调用 diffusers（text2img / img2img / depth2img / paint-by-example）生成图像，再做抠图/融合/细化
6) 输出以 base64 dataURI 列表返回前端展示
