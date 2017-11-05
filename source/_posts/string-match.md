---
title: String Match
date: 2017-04-30
tag: Algorithm
---
碰到了字符串匹配的需求，算法导论中文版翻译得还挺好的。
先从最简单的算法开始：
``` cpp
int matchA(string text, string pattern)
{
    int m = text.length();
    int n = pattern.length();
    for (int i = 0; i < m - n; ++i)
    {
        int j = 0;
        for (; j < n; ++j, ++i)
        {
            if (text[i] != pattern[j]) break;
            if (j == n - 1) return i - j;
        }
        i -= j;
    }
    return -1;
}
```
没什么特别的，其实还可以改写一下，变成：
``` cpp
int matchB(string text, string pattern)
{
    int n = text.length();
    int m = pattern.length();
    int i = 0, j = 0;
    while (i < n && j < m)
    {
        if (text[i] == pattern[j])
        {
            i += 1;
            j += 1;
        }
        else
        {
            i = i - j + 1;
            j = 0;
        }
    }
    if (j == m) return i - m;
    return -1;
}
```
上述代码和第一个逻辑上没有区别，只是把两个循环写成了一个，但这里可以把 i j 看做比较时文本的偏移和模式的偏移，这个概念后面还会用到。
接着就是有限自动机的概念，假设某个有限自动机满足每次输入文本的一个字符，改变后的状态对应之前输入的所有字符所组成的字符串（文本的一个前缀）的一个后缀的长度，满足该后缀是模式的前缀，且该长度是满足前面条件下的最大长度。使用上述有限自动机，字符串匹配就很简单了：
``` cpp
int matchC(string text, string pattern)
{
    int p = 0;
    int n = text.length();
    int m = pattern.length();
    auto transitionMap = computeTransitionMap(pattern);
    for (int i = 0; i < n; ++i)
    {
        p = transitionMap[p][text[i]];
        if (p == m)
        {
            return i + 1 - m;
        }
    }
    return -1;
}
```
剩下的问题就是如何构造符合条件的有限自动机，或者说是状态转移函数。构造这种状态转移函数只需要模式和字符集的信息就足够了，第一个想到的应该就是暴力循环穷举，下面给出的是最朴素的方法：
``` cpp
const vector<char> alphabet = { 'a', 'b', 'c', 'd', 'e', 'f',
                                'g', 'h', 'i', 'j', 'k', 'l',
                                'm', 'n', 'o', 'p', 'q', 'r',
                                's', 't', 'u', 'v', 'w', 'x', 'y', 'z' };
vector<map<char, int>> computeTransitionMap(string pattern)
{
    int m = pattern.length();
    vector<map<char, int>> result;
    for (int i = 0; i <= m; i++)
    {
        map<char, int> tmpMap;
        for (auto character : alphabet)
        {
            if (i < m && character == pattern[i])
            {
                tmpMap[character] = i + 1;
            }
            else
            {
                int j = 1, l = 0;
                for (; j < m + 1 && l < m + 1 - j; j++)
                {
                    if ((j == m ? character : pattern[j]) == pattern[l])
                    {
                        l += 1;
                    }
                    else
                    {
                        j -= l;
                        l = 0;
                    }
                }
                tmpMap[character] = l;
            }
        }
        result.push_back(tmpMap);
    }
    return result;
}
```
上面铺垫完了，下面正式介绍KMP，KMP只关注模式本身能够挖掘出的信息。这里又要引入一种状态转移函数 P，状态代表模式的一个前缀的开头和结尾的最长重合最长字符串的长度。构造这种状态转移函数，可以借鉴动态规划的思想。模式某个偏移 `i` 的状态 `P[i]` 和 `P[i - 1]` 有关，即如果相对应的偏移字符相等则有 `P[i] = P[i - 1] + 1`，类似的 `P[i] 和 P[P[i - 1]] P[P[P[i - 1]]] ...` 也有相同的关系。代码如下：
``` cpp
vector<int> computePrefixFunc(string pattern)
{
    int m = pattern.length();
    vector<int> prefixFunc(m + 1, 0);
    for (int i = 2; i <= m; ++i)
    {
        int p = prefixFunc[i - 1];
        while (p > 0 && pattern[i - 1] != pattern[p])
        {
            p = prefixFunc[p];
        }
        if (pattern[i - 1] == pattern[p])
        {
            prefixFunc[i] = p + 1;
        }
    }
    return prefixFunc;
}
```
至此，可以使用状态转移函数 P，来构造第一种有限自动机。或者我们可以在文本匹配的过程中直接使用状态函数 P，使用的方法和构造该状态函数的方法十分类似，将上文中的 matchB 稍加改造就得到了：
``` cpp
int KMPmatch(string text, string pattern)
{
    int m = pattern.length();
    int n = text.length();
    auto prefixFunc = computePrefixFunc(pattern);
    int i = 0, p = 0;
    while (i < n && p < m)
    {
        if (text[i] == pattern[p])
        {
            i += 1;
            p += 1;
        }
        else
        {
            i = i - p + 1;
            p = prefixFunc[p];
        }
    }
    if (p == m) return i - m;
    return -1;
}
```
PS: 写这种代码，先写几个 unit test，然后再动手实现。实现完了跑一遍 test，然后单独对某个测试调试。体验还是非常不错的。