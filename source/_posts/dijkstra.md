---
title: Dijkstra
date: 2016-01-30
tag: Algorithm
---
今天本来准备尝试一下hihocoder1138。结果卡在了dijkstra（只能用于无负边的图）上。以前只用python写过不用heap的实现，图均采用邻接矩阵来表示。代码如下：
``` python
def dijkstra(g, s):
    A = [float('inf') for idx in range(200)]
    A[s] = 0
    X = set([s])
    for idx in range(200):
        mini = [-1, float('inf')]
        for vertex in X:
            for neighbor in g[vertex]:
                if neighbor[0] not in X and mini[1] > A[vertex] + neighbor[1]:
                    mini[0] = neighbor[0]
                    mini[1] = A[vertex] + neighbor[1]
        X.add(mini[0])
        A[mini[0]] = mini[1]
    return  A
```
用heap构建priority queue来重写了一下，顺便记录了前驱结点，看起来顺眼多了：
``` python
from heapq import heappush, heappop
def dijkstra(g, s):
    vis = [0 for idx in range(len(g))]
    dist_pre = [(float('inf'),-1)for idx in range(len(g))]
    pq = [(0, s, -1)]
    while pq:
        (cost, ve, pre) = heappop(pq)
        if vis[ve] != 1: 
            vis[ve] = 1
            dist_pre[ve] = (cost,pre)
            for neighbor, weight in g[ve]:
                if vis[neighbor] == 1:
                    continue
                heappush(pq, (cost+weight, neighbor, ve))
    return dist_pre
```