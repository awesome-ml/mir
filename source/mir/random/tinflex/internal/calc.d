module mir.random.tinflex.internal.calc;

import std.traits: ReturnType, isFloatingPoint;
import mir.random.tinflex.internal.types : IntervalPoint;

/**
Splits an interval into two points.

Params:
    l = Left starting point of the interval
    r = Right ending point of the interval
Returns:
    Splitting point within the interval
*/
private auto arcmean(S)(S l, S r)
    if (isFloatingPoint!S)
{
    import std.math: atan, tan;
    import std.algorithm: swap;
    if (l > r)
        return tan(0.5 * (atan(l) + atan(r)));
    else
        return tan(0.5 * (atan(r) + atan(l)));
}

/**
Calculate the parameters for an interval.
Given an interval, determine it's type and hat and squeeze function.
Given these functions, compute the area and overwrite the references data type

Params:
    ipl = Left interval point
    ipr = Right interval point
    c   = Custom T_c family
*/
private void calcInterval(S)(ref IntervalPoint!S ipl, ref IntervalPoint!S ipr, in S c)
    if (isFloatingPoint!S)
{
    import mir.random.tinflex.internal.types : determineType;
    import mir.random.tinflex.internal.area: area, determineHatAndSqueeze;

    ipl.type = determineType(ipl, ipr);
    auto sh = determineHatAndSqueeze(ipl, ipr);
    ipl.hat = sh.hat;
    ipl.squeeze = sh.squeeze;

    // save area with the left interval
    ipl.hatA = area(sh.hat, ipl.x, ipr.x, ipl.tx, ipr.tx, c);
    ipl.squeezeA = area(sh.squeeze, ipl.x, ipr.x, ipl.tx, ipr.tx, c);

    import std.math: isInfinity;
    if (isInfinity(ipl.squeezeA))
        ipl.squeezeA = 0;
}

/**
Calculate the intervals for the Tinflex algorithm for a T_c family given its
density function, the first two derivatives and a valid start partitioning.
The Tinflex algorithm will try to split the intervals until a chosen efficiency
rho is reached.

Params:
    f0 = probability density function of the distribution
    f1 = first derivative of f0
    f1 = second derivative of f0
    c = T_c family
    points = non-overlapping partitioning with at most one inflection point per interval
    rho = efficiency of the Tinflex algorithm
    maxIterations = maximal number of iterations before Tinflex is aborted

Returns: Array of IntervalPoints
*/
protected IntervalPoint!S[] calcPoints(F0, F1, F2, S)
                            (in F0 f0, in F1 f1, in F2 f2,
                             in S c, in S[] points, in S rho = 1.1, int maxIterations = 10_000)
    if (is(ReturnType!F0 == S) && is(ReturnType!F1 == S) && is(ReturnType!F2 == S) &&
        (isFloatingPoint!S))
{
    import mir.random.tinflex.internal.transformations : transformToInterval;
    import std.container.dlist : DList;
    import std.range : dropBackOne;

    auto intervalTransform = transformToInterval(f0, f1, f2, c);

    auto ips = DList!(IntervalPoint!S)();
    foreach (i, p; points)
    {
        import std.algorithm.mutation : move;
        auto iv = intervalTransform(p);
        if (i > 0)
            calcInterval(ips.back, iv, c);
        ips.insertBack(iv);
    }

    auto nrIntervals = points.length;

    import std.stdio;

    S a_h;
    S a_s;
    void updateA()
    {
        a_h = 0;
        a_s = 0;
        auto i = 0;
        foreach (ref ip; ips)
        {
            a_h += ip.hatA;
            a_s += ip.squeezeA;

            writeln("i ", i);
            writeln("a_h", a_h);
            writeln("a_s", a_s);

            // last interval is only left-bounded
            if (i == nrIntervals - 2)
                break;
            i++;
        }
    }
    void printList()
    {
        auto i = 0;
        foreach (ref s; ips)
            writeln(i++, " ", s);
    }

    printList();

    updateA();
    writeln(ips.front);

    // Tinflex is not guaranteed to converge
    for (auto i = 0; i < maxIterations; i++)
    {
        if (a_h / a_s <= rho)
            break;

        S a_avg = (a_h - a_s) / (nrIntervals - 1);
        // first iteration: search only (we update the list online later)
        auto it = ips[];
        foreach (j; 0..nrIntervals - 1)
        {
            writeln(it.front);
            writeln("nrIntervals", nrIntervals);
            if (it.front.hatA - it.front.squeezeA > a_avg)
            {
                writefln("splitting %d-%d", j , j+1);
                import std.range : dropOne, takeOne;
                auto nextView = it.save.dropOne;

                writeln("nextView", nextView.front);

                // split the interval at the arcmean into two parts
                auto p = arcmean(it.front.x, nextView.front.x);
                IntervalPoint!S ip = intervalTransform(p);
                calcInterval(ip, nextView.front, c);
                writeln("----");
                writeln("nextView", nextView.front);
                writeln("ip", ip);

                writeln("front", it.front);
                calcInterval(it.front, ip, c);
                writeln("----");
                writeln("cur", it.front);
                writeln("ip", ip);

                writeln("new point", ip);

                // insert new middle part into linked list
                auto k = it.save;
                k.popFront();
                ips.insertBefore(k, ip);
                printList();
                nrIntervals++;
            }
            it.popFront();
        }
        updateA();
    }
    import std.array: array;
    // TODO: very important
    //ips.sort!`a.x < b.x`();
    auto arr = ips.array;
    return arr;
}

unittest
{
    auto f0 = (double x) => -x^^4 + 5 * x^^2 - 4;
    auto f1 = (double x) => 10 * x - 4 * x ^^ 3;
    auto f2 = (double x) => 10 - 12 * x ^^ 2;
    auto c = 1.5;

    import mir.random.tinflex.internal.calc: calcPoints;
    auto ips = calcPoints(f0, f1, f2, c, [-3.0, -1.5, 0.0, 1.5, 3], 1.1);

    // TODO: should be 45?
    assert(ips.length == 51);
}