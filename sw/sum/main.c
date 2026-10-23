// 求和程序：和 sw/hello 同一个 sum_to，但 n 从 volatile 变量读，编译器没法在编译时算出结果，
// 循环必须真的在核上跑完。返回 0 表示结果正确（1+2+...+100 = 5050）
static int sum_to(int n) {
    int s = 0;
    for (int i = 1; i <= n; ++i) s += i;
    return s;
}

volatile int n_in = 100;
volatile int result;

int main(void) {
    result = sum_to(n_in);
    return result == 5050 ? 0 : 1;
}
