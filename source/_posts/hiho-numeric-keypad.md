---
title: Hihocoder Numeric Keypad
date: 2016-02-20
tag: OJ
---
复习一下dfs。
``` cpp
#include <cstdio>
#include <iostream>
#include <cstring>
#include <string>
using namespace std;
int t, len, kd[505], result[505];
bool go[10][10];
string k;
void init()
{
    memset(kd, 0, sizeof(kd));
    memset(result, 0, sizeof(result));
}
void printResult()
{
    for(int i=1; i<=len; ++i)
        cout << result[i];
    cout << endl;
}
int getMax(int last)
{
    int maxn = -1;
    for(int i=9; i>=0; i--)
    {
        if(go[last][i])
        {
            maxn = i;
            break;
        }
    }
    return maxn;
}
bool dfs(int depth, int last, bool below)
{
    if(depth > len)
    {
        printResult();
        return true;
    }
    if(below)
    {
        int maxn = getMax(last);
        if(maxn == -1)
            return false;
        for(int i=depth; i<= len; i++)
            result[i] = maxn;
        printResult();
        return true;
    }
    for (int i=9; i>=0; --i)
    {
        if(i <= kd[depth]&&go[last][i])
        {
            result[depth] = i;
            if(dfs(depth+1, i, i<kd[depth]))
            {
                return true;
            }
        }
    }
    return false;
}
int main()
{
    scanf("%d", &t);
    memset(go, 0, sizeof(bool)*100);
    for (int i=0; i<10; i++)
    {
        go[i][i] = true;
        if(i==0) continue;
        for (int j=i; j<10; j++)
        {
            if(i%3==1)
            {
                go[i][j]=true;
                go[i][0]=true;
            }
            if(i%3==2&&(j%3==2||j%3==0))
            {
                go[i][j]=true;
                go[i][0]=true;
            }
            if(i%3==0&&j%3==0) go[i][j]=true;
        }
    }
    for(int i=0; i<t; ++i)
    {
        init();
        cin >> k;
        len = k.length();
        for(int i=1; i<=len; i++)
            kd[i] = k[i-1] - 48;
        dfs(1,1, false);
    }
}
```