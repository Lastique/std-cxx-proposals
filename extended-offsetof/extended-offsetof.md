<table>
<tr><td>Document number:</td><td>Nnnnn=yy-nnnn</td></tr>
<tr><td>Date:</td><td>2016-10-23</td></tr>
<tr><td>Project:</td><td>ISO JTC1/SC22/WG21: Programming Language C++</td></tr>
<tr><td>Author:</td><td>Andrey Semashev &lt;andrey.semashev at gmail dot com&gt;</td></tr>
<tr><td>Reply-to:</td><td>Andrey Semashev &lt;andrey.semashev at gmail dot com&gt;</td></tr>
</table>

# Introduction

This proposal introduces *stable layout* concept and extends `offsetof` to support more types.

# Motivation and Scope

Currently (according to N4606), `offsetof` is required to only work for standard-layout classes. This definition prohibits portable code from using `offsetof` in useful contexts. For instance, consider the following classes:

```cpp
struct A
{
    int a;
};

struct B : A
{
    int b;
};
```

Imagine that an application needs to pass objects of type `B` between multiple processes via shared memory. The classes are trivially copyable, so the simplest way to do that is to use `std::memcpy`. Occasionally, a process needs only one member of `B` (say, `B::b`). In order to extract it from the shared memory storage occupied by the complete object of `B`, the application needs to know the offset of `B::b` relative to the starting address of the `B` object. This offset is normally provided by `offsetof`, but formally it cannot be applied in this case because `B` is not a standard-layout class since more than one class in the hierarchy has non-static data members.

It is understandable that the current definition of `offsetof` in C++ mostly just refers to the C standard, for the best compatibility with C. C++ offers more advanced means for type definition, including type inheritance, methods, constructors and destructors, yet it doesn't extend `offsetof` to support these types even when possible. This proposal attempts to mitigate this omission.

# Impact On the Standard

This proposal is pure extension to the C++ language and standard library. Its intent is to define behavior that was previously not defined, in a way that most current implementations already work. No existing valid code is made invalid or changes its behavior.

# Design Decisions

## Trivially-copyable types

With the current standard, it should be possible to extend `offsetof` to support at least trivially-copyable types. Given the `A` and `B` classes from the earlier example, the following code is expected to work:

```cpp
B b1, b2;
int* p = &b2.b;

b1.a = 1;
b1.b = 2;

std::memcpy(&b2, &b1, sizeof(B));

assert(*p == 2);
```

This follows from [basic.types]/3. In particular, this also means that the relative position of `B::b` within `B` is constant and does not depend on the particular object of `B`. This is enough for `offsetof` to be able to operate on this type as expected.

## Non-trivially-copyable classes

It is the author's opinion that trivial copyability, or copyability at all, is not the property that defines binary layout of the type. For example, let's slightly modify the previously given `B` class as follows:

```cpp
class C : public A
{
public:
    int c;
    char str[1024];

    C() : c(10)
    {
        str[0] = '\0';
    }

    C(C const& that) : c(that.c)
    {
        std::strcpy(str, that.str);
    }

    C& operator= (C const& that)
    {
        c = that.c;
        std::strcpy(str, that.str);
        return *this;
    }
};
```

The type `C` is no longer trivially-copyable, but is it no longer viable for inter-process communication? Is the mere presence of user-defined copy constructor and assignment operator the limiting factor that prevents this? The author believes not, and indeed in the most widespread ABIs, ([IA-64 C++ ABI](https://mentorembedded.github.io/cxx-abi/abi.html) as well as Microsoft Windows x64 ABI) binary layout does not depend on presence of the special member functions. The author believes that there is no practical benefit in leaving the opportunity to do otherwise. This proposal aims to add support for `offsetof` for such types.

## Classes with virtual functions

The most common implementation of virtual functions involves a virtual function table (vtable), a pointer to which is stored as a hidden member in class objects. The size and position of this hidden member is constant, so in most cases virtual functions do not preclude `offsetof` from working as expected.

However, it is possible that other implementations exist. For instance, an implementation could use another hidden field that would contain an offset to the data members of the final class object. Also, classes with virtual functions are not applicable for interprocess communication as described in the motivating example. For these reasons this proposal does not include support for classes with virtual functions. A future proposal could add such support if the need appears.

## Classes with virtual base classes

Like virtual functions, virtual base classes also typically introduce a hidden data member (vtordisp). However, unlike virtual functions, this member is used to calculate address of the virtual base class subobject in runtime. It is possible to perform that calculation in compile time when the final type of the complete object is known (for instance, if the final object is visible in the context of that calculation, or the class is marked as `final`), but in general the fact that runtime resolution may be required rules out support for such classes in `offsetof`.

# Impact on existing implementations

The currently widespread compilers (GCC 6.2, Clang 3.8) all support `offsetof` for classes `A`, `B` and `C` described before, although the compilers emit warnings. The implementation complexity is expected to be minimal.

# Technical Specifications

## Stable-layout classes concept

Since the standard does not currently define a suitable category of types, this proposal introduces the concept of a *stable-layout class*, which is a class that satisfies the following conditions:

 - the class must not have virtual base classes
 - the class must not have virtual functions

For a stable-layout class, it is guaranteed that relative positions of non-static data members will be constant and statically known across all objects of that class.

Note that a stable-layout class is allowed to have non-static data members that are not stable-layout themselves. This is so because object representation ([basic.types]/4) of the member constitutes a contiguous sequence of bytes within the storage allocated for the enclosing complete object. The size and alignment of the member are known at compile time and thus the aforementioned guarantee of the stable binary layout of the enclosing class can be fulfilled.

## Additional restrictions on member specification

The definition of `offsetof(type, member-designator)` in [support.types.layout]/1 refers to C standard, and it only requires `&(t.member-designator)` to evaluate to an address constant (here, `t` is an object of class `type`). Since this proposal allows using `offsetof` with non-trivial types, `member-designator` can now identify a reference member. Taking address of a reference member would result in address of a referred object, which is not the intended effect of `offsetof`. For this reason, this proposal prohibits the use of references in `member-designator`; the behavior is undefined if this requirement is violated. Note that this rule applies if references are used at any level of `member-designator`, if it identifies a nested member. For example:

```cpp
struct Bad
{
    int& n;
    A& a;
    int x;
};

offsetof(Bad, n); // undefined behavior, Bad::n is a reference
offsetof(Bad, a.a); // undefined behavior, Bad::a is a reference
offsetof(Bad, x); // ok, returns offset of Bad::x
```

Also, if `member-designator` identifies a nested member, the requirements on `type` should also apply to all types of the members mentioned in `member-designator`, except the last one.

```cpp
struct D
{
    A a;
};

struct V : virtual C
{
};

struct E
{
    C c;
    D d;
    V v;
};

offsetof(E, d.a.a); // ok, E, D and A are stable-layout
offsetof(E, v.c); // conditionally-supported, not allowed by this proposal because V is not stable-layout
```

## Proposed wording

The proposed wording below is given relative to N4606.

* Add a new paragraph after [class]/7:

    <ins>A <i>stable-layout class</i> is a class:
    <ul>
    <li>that has no virtual base classes (10.1)</li>
    <li>that has no virtual functions (10.3)</li>
    </ul>
    For any object <i>x<sub>i</sub></i> of a stable-layout class <i>X</i>, each non-static data member address relative to the starting address of <i>x<sub>i</sub></i> shall be constant and equal to the corresponding address in any other <i>x<sub>j</sub></i>.<br/>
    <i>[Note:</i> A stable-layout class can contain members that are not stable-layout themselves. <i>&mdash; end note]</i></ins><br/>

* Modify [class]/8:

    A <i>standard-layout struct</i> is a standard-layout class defined with the <i>class-key</i> <tt>struct</tt> or the <i>class-key</i> <tt>class</tt>. A <i>standard-layout union</i> is a standard-layout class defined with the <i>class-key</i> <tt>union</tt>.<ins> A <i>stable-layout struct</i> is a stable-layout class defined with the <i>class-key</i> <tt>struct</tt> or the <i>class-key</i> <tt>class</tt>. A <i>stable-layout union</i> is a stable-layout class defined with the <i>class-key</i> <tt>union</tt>.</ins><br/>

* Modify [support.types.layout]/1:

    The macro <tt>offsetof</tt>(<i>type</i>, <i>member-designator</i>) has the same semantics as the corresponding macro in the C standard library header <tt>&lt;stddef.h&gt;</tt>, but accepts a restricted set of <i>type</i><ins> and <i>member-designator</i></ins> arguments in this International Standard.<ins> The following restrictions apply:
    <ul>
    <li>the <i>type</i> argument shall identify a stable-layout class (Clause 9);</li>
    <li>if the <i>member-designator</i> argument identifies a member <i>m</i> that is nested <i>N</i> levels deep in members <i>n<sub>N</sub></i>, then the type of <i>n<sub>i</sub></i> shall be a (possibly <i>cv</i>-qualified) stable-layout class or an array thereof, for 0 &lt;= <i>i</i> &lt;= <i>N</i>.</li>
    </ul>
    </ins>Use of the <tt>offsetof</tt> macro with <del>a type</del><ins>types</ins> other than <del>a standard-layout class (Clause 9)</del><ins>specified above</ins> is conditionally-supported. The expression <tt>offsetof</tt>(<i>type</i>, <i>member-designator</i>) is never type-dependent (14.6.2.2) and it is value-dependent (14.6.2.3) if and only if <i>type</i> is dependent. The result of applying the <tt>offsetof</tt> macro to a static data member or a function member is undefined.<ins> If <i>member-designator</i> refers to a reference data member at any member nesting level or identifies a reference data member, the result of the <tt>offsetof</tt> macro is undefined.</ins> No operation invoked by the <tt>offsetof</tt> macro shall throw an exception and <tt>noexcept(offsetof(type, member-designator))</tt> shall be <tt>true</tt>.<ins><br/>
    <i>[Example:</i><code><pre>struct A { int a; };
    struct V : public virtual A { int x; };
    struct R
    {
        A a;
        A&amp; r;
        V v;
    };

    void f() {
        offsetof(R, v);   // ok, R is a stable-layout class
        offsetof(R, a.a); // ok, both R and A are stable-layout classes
        offsetof(R, v.x); // conditionally-supported, V is not a stable-layout class
        offsetof(R, r);   // undefined behavior, R::r is a reference
        offsetof(R, r.a); // the same
    }</pre></code><i>&mdash; end example]</i>
    </ins>

# Acknowledgements

 - Thanks to all paricipants in the discussion of the proposal at the [std-discussion] mailing list, and in particular to "Myriachan" &lt;myriachan at gmail dot com&gt; for the suggested example showing that trivially-copyable types should be supported by `offsetof`.

# References

 - [IA-64 C++ ABI](https://mentorembedded.github.io/cxx-abi/abi.html)
