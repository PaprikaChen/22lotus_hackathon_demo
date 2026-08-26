# 画廊 CG 资源（gallery CG）

每个 `.tres` 是一个 `CGEntry`（id / 标题 / 全图 / 缩略图 / 说明 / 排序）。
`GalleryManager` 启动时扫这个目录自动注册——丢一个新 `.tres` 进来它就出现在
画廊里。

规则：

- `id` 一经写进 `user://gallery.json` **不得改名**；标题、图、说明随时可换。
- `sort_order` 决定画廊里的位置，**不要依赖文件名或解锁顺序**。
- 解锁状态**不在这里**，也**不在存档槽里**：CG 收集跨三个存档槽共享，
  存在全局文件 `user://gallery.json`（见 `scripts/autoload/gallery_manager.gd`）。
  删存档不会丢收集。
- 谁来解锁：**StoryDirector**。CG 解锁是剧情后果，写在 Director 的 `_on_*` 里，
  和「写 Flag / 推进信物」同一类。不要让 Cutscene 或 UI 自己解锁。

`cg_placeholder_01/02.tres` 是**占位**，拿 `icon.svg` 当图，只为跑通管线。
真正的 CG 交付后替换它们（或删掉换成真资源）——这两个 id 还没进过任何玩家
存档，可以自由改名。
