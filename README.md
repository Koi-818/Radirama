![1744471673384](https://github.com/user-attachments/assets/fb617cd4-fa2b-4883-8d74-bdff22910b54)

# Radirama 插件

**Radirama** 是一个为 Godot 引擎设计的音频时间线管理插件，用于创建和播放基于 JSON 的时间线序列，支持多种事件类型，包括音频播放、等待、停止、选择、震动以及时间线跳转。插件提供了一个直观的编辑器界面，方便开发者管理和预览时间线，特别适合交互式叙事游戏、音频驱动的场景或需要复杂时间线控制的项目。

## 当前版本
- **v0.43**（包含时间线跳转功能）
- 仓库：`https://github.com/Koi-818/Radirama`

## 功能亮点
- **JSON 时间线**：通过 JSON 文件定义时间线，支持灵活的事件序列。
- **多种事件类型**：
  - `audio`：播放语音、音乐或音效，支持淡入淡出。
  - `wait`：暂停时间线指定时长。
  - `stop`：停止音乐或音效。
  - `choice`：提供玩家选择，支持标签跳转。
  - `vibrate`：触发手柄震动效果。
  - `jump`（v0.43 新增）：跳转到另一个 JSON 时间线文件。
- **时间线编辑器**：内置编辑器，支持创建、修改、预览和保存时间线。
- **暂停与保存**：支持暂停时间线并保存进度（包括音频位置和标签）。
- **无障碍支持**：集成文本转语音 (TTS)，提示暂停、选择等状态。
- **跨平台**：兼容 Godot 支持的所有平台，特别优化手柄输入和震动。

## 安装

1. **下载插件**：
   - 克隆或下载本仓库：
     ```bash
     git clone https://github.com/Koi-818/Radirama.git
     ```
   - 或从 [Releases](https://github.com/Koi-818/Radirama/releases) 下载最新版本。
2. **添加到 Godot 项目**：
   - 将插件文件夹（`addons/Radirama`）复制到你的 Godot 项目根目录下的 `addons/` 文件夹。
   - 目录结构示例：
     ```
     your_project/
     ├── addons/
     │   ├── Radirama/
     │   │   ├── AudioTimeline.gd
     │   │   ├── TimelineEditor.gd
     │   │   ├── Timelines/
     │   │   └── ...
     ├── project.godot
     └── ...
     ```
3. **启用插件**：
   - 打开 Godot 编辑器 → **项目** → **项目设置** → **插件**。
   - 找到 `Radirama`，启用它（可能需要 `plugin.cfg`，见下文）。
4. **配置时间线**：
   - 在 `res://addons/Radirama/Timelines/` 创建 JSON 时间线文件（例如 `test.json`）。
   - 示例 JSON：
     ```json
     [
         {"type": "audio", "voice": "res://audio/example.wav", "tag": "intro"},
         {"type": "wait", "duration": 2.0},
         {"type": "jump", "target_timeline": "res://addons/Radirama/Timelines/another.json"}
     ]
     ```

## 使用方法

### 1. 配置时间线
- **创建 JSON 文件**：
  - 在 `res://addons/Radirama/Timelines/` 创建时间线文件，格式为 JSON 数组。
  - 每个元素是一个事件对象，包含 `type` 和其他属性（见“事件类型”）。
- **编辑器操作**：
  - 打开 Godot 编辑器，确保插件启用。
  - 访问时间线编辑器（需配置场景，参考 `TimelineEditor.gd`）。
  - 使用按钮添加事件（音频、等待等），设置属性（如音频路径、时长）。
  - 保存时间线到 JSON 文件（默认路径 `res://addons/Radirama/Timelines/`）。

### 2. 播放时间线
- **场景设置**：
  - 创建一个节点，附加 `AudioTimeline.gd` 脚本。
  - 设置 `timeline_path` 属性，指向 JSON 文件，例如：
    ```gdscript
    @export var timeline_path: String = "res://addons/Radirama/Timelines/test.json"
    ```
  - 确保场景包含以下子节点：
    - `VoiceAudio`（AudioStreamPlayer）
    - `MusicAudio`（AudioStreamPlayer）
    - `SFXAudio`（AudioStreamPlayer）
- **运行**：
  - 启动游戏，插件会自动加载并播放时间线。
  - 支持手柄输入：
    - `pause_save`：暂停并保存。
    - `resume_game`：继续。
    - `choice_left` / `choice_right`：选择选项（LT/RT 键）。

### 3. 事件类型
以下是支持的事件类型及其属性：

| 类型       | 属性                                                                 | 描述                              |
|------------|----------------------------------------------------------------------|-----------------------------------|
| `audio`    | `voice` (String), `music` (String), `sfx` (String), `tag` (String)   | 播放音频，支持语音、音乐、音效，带标签。 |
| `wait`     | `duration` (float)                                                  | 暂停指定秒数。                    |
| `stop`     | `music` (bool), `sfx` (bool)                                        | 停止音乐或音效。                  |
| `choice`   | `options` (Array[{text: String, label: String}])                    | 显示选择，设置标签跳转。          |
| `vibrate`  | `weak_magnitude` (float), `strong_magnitude` (float), `duration` (float) | 触发手柄震动。                    |
| `jump`     | `target_timeline` (String)                                          | 跳转到另一个 JSON 时间线文件。    |

- **示例时间线**：
  ```json
  [
      {
          "type": "audio",
          "voice": "res://audio/intro.wav",
          "music": "res://audio/background.mp3",
          "tag": "start"
      },
      {
          "type": "choice",
          "options": [
              {"text": "继续冒险", "label": "continue"},
              {"text": "返回村庄", "label": "village"}
          ]
      },
      {
          "type": "jump",
          "target_timeline": "res://addons/Radirama/Timelines/village.json",
          "tag": "village"
      }
  ]
  ```

### 4. 保存与加载
- **保存**：
  - 按 `pause_save` 输入（默认映射），保存当前进度（索引、音频位置、标签、时间线路径）到 `user://saves/my_slot.json`。
- **加载**：
  - 调用 `load_game()` 函数，恢复保存的进度并继续播放。

## 依赖
- **Godot 引擎**：推荐 4.x 版本（插件基于 Godot 4 开发，可能需调整以兼容 3.x）。
- **音频文件**：支持 `.wav` 和 `.mp3` 格式，需放置在项目路径下。
- **手柄支持**：可选，用于震动和选择功能（需配置输入映射）。
- **TTS**：依赖 Godot 的 `DisplayServer.tts_speak`，确保目标平台支持。

## 开发状态
- **当前版本**：v0.43（2025年4月）
- **已实现**：
  - 完整的时间线播放和编辑功能。
  - 新增 `jump` 事件，支持跨时间线跳转。
  - 暂停、保存、加载功能。
- **计划功能**：
  - 增强编辑器 UI，支持直接添加 `jump` 事件。
  - 优化性能，减少内存占用。
  - 添加更多事件类型（如动画触发）。
- **已知问题**：
  - 编辑器暂不支持 `jump` 事件的属性编辑（需手动修改 JSON）。
  - TTS 在某些平台可能不稳定。

## 贡献
欢迎为 Radirama 插件贡献代码或建议！请按照以下步骤：
1. 克隆仓库：
   ```bash
   git clone https://github.com/Koi-818/Radirama.git
   ```
2. 创建分支：
   ```bash
   git checkout -b feature/你的功能
   ```
3. 提交更改：
   ```bash
   git commit -m "添加新功能"
   git push origin feature/你的功能
   ```
4. 在 GitHub 提交 Pull Request，描述你的更改。
5. 遵循 Godot 编码规范，确保兼容性。


## 联系
- 作者：Koi-818
- GitHub Issues：`https://github.com/Koi-818/Radirama/issues`
- 反馈与建议欢迎提交！

## 致谢
- Godot 社区的灵感与支持。
- 所有测试者和贡献者（欢迎加入！）。

---

**让你的 Godot 项目通过 Radirama 讲述精彩的故事！**
```
