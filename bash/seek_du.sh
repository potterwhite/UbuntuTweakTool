#!/bin/bash

# 检查是否提供了目标路径参数
if [ -z "$1" ]; then
  echo "错误: 请提供一个目标路径作为参数。"
  echo "用法: $0 <目标目录>"
  exit 1
fi

target_dir="$1"

# 检查提供的路径是否存在并且是一个目录
if [ ! -d "$target_dir" ]; then
  echo "错误: '$target_dir' 不是一个有效的目录。"
  exit 1
fi

echo "正在分析目录: $target_dir (按占用空间从大到小排序)"
echo "----------------------------------------------------"

# 临时存储目录大小和路径信息，用于排序
# 使用 find ... -print0 和 xargs -0 更安全地处理特殊字符的文件名
# 使用 du -sb 获取字节大小，便于排序
# 使用 sort -nr 进行数字反向排序（从大到小）
# 使用 cut 提取排序后的路径
# 最后使用 while read 处理排序后的路径列表

count=0
while IFS= read -r subdir_path; do
  # 增加计数器
  ((count++))

  # 获取目录的基本名称 (不含路径)
  subdir_name=$(basename "$subdir_path")

  # 再次使用 du -sh 获取人类可读的大小用于显示
  # 这里需要再次计算，因为排序是基于字节数的
  size_human=$(du -sh "$subdir_path" | awk '{print $1}')

  # 格式化输出
  printf "%d. 名称: %s, 占用空间: %s\n" "$count" "$subdir_name" "$size_human"

done < <(find "$target_dir" -maxdepth 1 -mindepth 1 -type d -print0 | \
         xargs -0 -I {} du -sb "{}" | \
         sort -nr | \
         cut -f2-)
         # cut -f2- 用于提取 du 输出的第二列及之后的所有内容（即路径）

echo "----------------------------------------------------"
# 获取实际找到并处理的目录数量 (如果上面循环没执行，count 可能是 0)
# 可以重新计算或使用之前的 count 值
final_count=$(find "$target_dir" -maxdepth 1 -mindepth 1 -type d | wc -l)
echo -e "总共找到 $final_count 个第一级子目录。\n" 

exit 0
