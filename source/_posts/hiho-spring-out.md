---
title: hihocoder Spring Out
date: 2016-02-23
tag: OJ
---
``` cpp
#include <iostream>
#include <cstdio>
using namespace std;
int prank[1005][1005];
int main(){
    int n, k;
    cin >> n >> k;
    int r;
    for(int i=0; i<n; ++i)
        for(int j=0; j<=k; ++j)
        {
            cin >> r;
            prank[i][r] = j;
        }
    int result = 0;
    for(int i=k; i>0; --i)
    {
        int vote=0;
        for(int j=0; j<n; j++)
        {
            if (prank[j][i] < prank[j][result])
                vote++;
        }
        if(vote > n/2)
        {
            result = i;
        }
    }
    if(result)
        cout << result << endl;
    else
        cout << "otaku\n" << endl;
}
```