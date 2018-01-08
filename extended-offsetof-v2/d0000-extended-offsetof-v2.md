<table>
<tr><td>Title:</td><td>Extending <tt>offsetof</tt> for All Types</td></tr>
<tr><td>Document number:</td><td>D0000R0</td></tr>
<tr><td>Date:</td><td>2018-01-05</td></tr>
<tr><td>Project:</td><td>ISO JTC1/SC22/WG21: Programming Language C++</td></tr>
<tr><td>Audience:</td><td>EWG, LEWG</td></tr>
<tr><td>Reply-to:</td><td>Andrey Semashev &lt;andrey.semashev at gmail dot com&gt;</td></tr>
</table>

# 1. Introduction

This proposal extends the set of types `offsetof` is required to support. It builds upon the feedback received for the not accepted [P0545R0](http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0545r0.html) (Supporting <tt>offsetof</tt> for Stable-layout Classes) proposal, which was to broaden the set of types supported by `offsetof` either by relaxing standard-layout class restrictions or by specifying `offsetof` for more categories of types, without introducing new ones. While relaxing standard-layout class may be useful on its own, it does not coincide with the intention of the original proposal, which was to improve `offsetof`. Also, changing specification of standard-layout class might require coordination of more parts of the standard and possibly have effect on compatibility with C. Therefore this proposal takes the second approach. It does not preclude future proposals regarding standard-layout classes.

This paper inherits much of the motivation presented in P0545R0. Some of the sections from that proposal were updated, extended and represented in this document for convenience.

# 2. Motivation and Scope

## 2.1. Non-standard-layout Classes for Data Exchange

Currently (according to [N4713](http://open-std.org/JTC1/SC22/WG21/docs/papers/2017/n4713.pdf), [support.types.layout]/1), `offsetof` is required to work for only standard-layout classes. This definition prohibits portable code from using `offsetof` in other useful contexts. For instance, consider the following classes:

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

Imagine that an application needs to pass objects of type `B` between multiple processes via shared memory. The classes are trivially copyable, so the simplest way to do that is to use `std::memcpy`. Occasionally, a process needs only one member of `B` (say, `B::b`). In order to extract it from the shared memory storage occupied by the complete object of `B`, the application needs to know the offset of `B::b` relative to the starting address of the `B` object. This offset is normally provided by `offsetof`, but formally the macro cannot be applied in this case because `B` is not a standard-layout class. That is because more than one class in the hierarchy has non-static data members.

It is understandable that the current definition of `offsetof` in C++ mostly just refers to the C standard, for the best compatibility with C. However, C++ offers more advanced means for type definition, including type inheritance, methods, constructors and destructors, yet it doesn't extend `offsetof` to support these types even when feasible. This proposal attempts to mitigate this omission.

### 2.1.1. Alternative Solutions

A number of alternative solutions could be used to achieve the desired functionality without extending `offsetof`. This section offers a discussion of these alternatives and the reasoning for still preferring `offsetof` extension.

#### 2.1.1.1. Convert structures to standard layout

One possible alternative is to convert `B` from the above example to a standard-layout class, replacing inheritance with encapsulation like this:

```cpp
struct standard_layout_B
{
    A a;
    int b;

    standard_layout_B() = default;
    standard_layout_B(A const& a_) : a(a_) {}
    operator A& () { return a; }
    operator A const& () const { return a; }
};
```

While this approach solves the problem of formal incompatibility with `offsetof`, it adds problems of its own:

1. It contradicts the intent of the developer, if `B` was supposed to be a natural extension of `A` (i.e. `B` should have been derived from `A` in every other case, if not for `offsetof`). As a result, it obscures the program design, making it more difficult to understand and maintain.
2. The `standard_layout_B` class is not equivalent to `B` on a semantic level. For instance, since `standard_layout_B` does not inherit from `A`, pointers to `standard_layout_B` cannot be converted to pointers to `A` ([conv.ptr]/3); pointers to members of `A` cannot be converted to pointers to members of `standard_layout_B` ([conv.mem]/2). Standard type traits, such as `is_base_of` will also report `standard_layout_B` and `A` as unrelated. This limits interchangeability between `A` and `standard_layout_B` in the surrounding code.
3. The `standard_layout_B` class is not equivalent to `B` on a syntactic level. Members of `A` are not members of `standard_layout_B`, and every mention of an `A` member will have to involve either mentioning `standard_layout_B::a` or obtaining a reference to it (e.g. by calling the type conversion operator defined in `standard_layout_B`). This greatly complicates writing generic code that is supposed to work with `A`, `B` and other classes that derive from `A`, similar to `B`. With multiple such `B`s the approach quickly shows poor scalability.

To illustrate these problems, let's consider the following class hierarchy, which is a simplified version of a real code. Imagine a media processing application that consists of multiple processes exchanging video and audio frames via shared memory. Each frame is associated with a set of metadata expressed by one of these structures:

```cpp
struct frame { long timestamp; };

struct audio_frame : frame { ... };
struct video_frame : frame { ... };

struct raw_audio_frame : audio_frame { ... };
struct encoded_audio_frame : audio_frame { ... };

struct raw_video_frame : video_frame { ... };
struct encoded_video_frame : video_frame { ... };
```

Note that the hierarchy may be deeper and may include, for example, classes that correspond to particular video and audio codecs. Rewriting them as standard-layout classes would result in this:

```cpp
struct frame { long timestamp; };

struct audio_frame { frame f; ... };
struct video_frame { frame f; ... };

struct raw_audio_frame { audio_frame af; ... };
struct encoded_audio_frame { audio_frame af; ... };

struct raw_video_frame { video_frame vf; ... };
struct encoded_video_frame { video_frame vf; ... };
```

Now, in order to reference `frame::timestamp` the user's code has to be different, depending on the actual type of the class the code is dealing with:

```cpp
frame f;
audio_frame af;
video_frame vf;
raw_audio_frame raf;
encoded_audio_frame eaf;
raw_video_frame rvf;
encoded_video_frame evf;

f.timestamp = 10;
af.f.timestamp = 10;
vf.f.timestamp = 10;
raf.af.f.timestamp = 10;
eaf.af.f.timestamp = 10;
rvf.vf.f.timestamp = 10;
evf.vf.f.timestamp = 10;
```

A possible workaround for this is to introduce type traits or accessors to all members of the structures (including data members and functions). For example:

```cpp
struct frame
{
    long m_timestamp;

    long& timestamp() noexcept { return m_timestamp; }
    long const& timestamp() const noexcept { return m_timestamp; }
};

struct audio_frame
{
    frame m_f;
    ...

    long& timestamp() noexcept { return m_f.timestamp(); }
    long const& timestamp() const noexcept { return m_f.timestamp(); }
    ...
};

struct video_frame
{
    frame m_f;
    ...

    long& timestamp() noexcept { return m_f.timestamp(); }
    long const& timestamp() const noexcept { return m_f.timestamp(); }
    ...
};

struct raw_audio_frame
{
    audio_frame m_af;
    ...

    long& timestamp() noexcept { return m_af.timestamp(); }
    long const& timestamp() const noexcept { return m_af.timestamp(); }
    ...
};

struct encoded_audio_frame
{
    audio_frame m_af;
    ...

    long& timestamp() noexcept { return m_af.timestamp(); }
    long const& timestamp() const noexcept { return m_af.timestamp(); }
    ...
};

struct raw_video_frame
{
    video_frame m_vf;
    ...

    long& timestamp() noexcept { return m_vf.timestamp(); }
    long const& timestamp() const noexcept { return m_vf.timestamp(); }
    ...
};

struct encoded_video_frame
{
    video_frame m_vf;
    ...

    long& timestamp() noexcept { return m_vf.timestamp(); }
    long const& timestamp() const noexcept { return m_vf.timestamp(); }
    ...
};
```

While that unifies access to all fields of the structures, this also adds a lot of verbosity to the structures' definition. Adding, removing, or modifying any member of the base structures also requires similar modifications to all containing structures. This is much more tedious and error prone than the original code that used inheritance. The author is also convinced that the original code is a more appropriate design choice from the standpoint of semantic relations between the classes, as each derived class is a specialization and extension of its base classes.

##### 2.1.1.1.1. Aren't standard-layout classes required for inter-process communication anyway?

The short answer to that question is no, they are not required. As long as the programs exchanging data are built with compilers that implement the same ABI specification, or different ABI specifications that are compatible with regard to types' representation, these programs shall be compatible. This guarantee is given by the ABI specification, not by the C++ standard. The standard-layout property by itself does not guarantee binary compatibility, nor is it a required precondition for one. What standard-layout offers is a set of restrictions on C++ types so that they are compatible, on the language level, with a similar structure in another language (primarilly, the C language), provided that ABI specifications for the two languages are compatible. However, when compatibility with languages other than C++ is not required, the restrictions imposed by a standard-layout class can be too limiting. Even when the two processes comply with different ABIs that are not fully compatible, there can be a less restricted subset of C++ features that can be used portably.

The existing practice on most current platforms is that there is one C++ ABI specification per target architecture that is supported by most or all compilers on the platform. One notable exception is Windows, where there are two commonly used ABIs: Microsoft's (supported by MSVC, Intel compiler, clang-cl) and GCC (supported by MinGW, MinGW-w64, clang). While different, these ABIs are still very compatible with regard to types' representation: all fundamental types, enums, and simple structures like `A`, `B` and `C` defined in this proposal, are compatible. On the other hand, even a structure as simple as `A` could not have been used for data exchange if the two ABIs defined their `int` representation differently.

It should also be noted that the programs that use C++ structures directly for data exchange are often parts of the same framework and are compiled by the same compiler, thus eliminating any potential ABI incompatibility. When data exchange is supposed to be carried out with external parties, it is normal to expect a more formal description of the exchange protocol that does not include any C/C++ structures.

#### 2.1.1.2. Use serialization for data exchange

Another alternative solution to the original problem would be to implement (de)serialization of `A` and `B` to a binary format understood by all processes involved in data exchange. Such a format could potentially allow a fast extraction of a single data member without having to decode the full structure, thus eliminating the need for `offsetof` in the first place. This approach is often used in other types of data exchange, such as network-based or file-based data exchange.

The downside of serialization is that it entails a certain cost, on both development and runtime performance. Let's consider the following, probably the simplest implementation of serialization for `B`:

```cpp
struct serialized_B
{
    int A_a; // corresponds to A::a
    int B_b; // corresponds to B::b
};

void serialize(B const& b, unsigned char* p)
{
    serialized_B s;
    s.A_a = b.a;
    s.B_b = b.b;

    std::memcpy(p, &s, sizeof(s));
}

void deserialize(const unsigned char* p, B& b)
{
    serialized_B s;
    std::memcpy(&s, p, sizeof(s));

    b.a = s.A_a;
    b.b = s.B_b;
}
```

The above code needs to be written for every `B` (and probably `A` to maintain the same API for storing and loading the structures to/from shared memory) and kept in sync with the structures as the code evolves. There is also a runtime overhead if the compiler is not able to optimize away the extra memory copy in `serialize()`/`deserialize()` (e.g. if `serialized_B` has different binary representation than `B`).

This imposed cost is likely justified if binary format of messages is important, like when the messages are transmitted to another machine and can be received by a foreign receiver. That is not the case when the messages are exchanged locally, between the processes that are already binary compatible; the cost can be avoided in this case.

## 2.2. Classes with Virtual Functions and Virtual Base Classes

Although such classes are not suitable for data exchange, there may be use cases where `offsetof` would be useful with them as well. For example, an algorithm supporting heterogenous input (e.g. elements of different types in a heterogenous intrusive sequence) could be implemented more efficiently if it had information about offsets to the relevant data in the elements of the sequence. The alternative implementations typically involve some sort of visitation and dynamic dispatch, which is likely more expensive in terms of performance and code size than pointer manipulation using offsets.

Another reason to support `offsetof` for as many categories of types as possible is to reduce the learning curve for less experienced programmers. The topic of `offsetof`, including why it doesn't support types other than standard-layout classes, is recurring on resources like StackOverflow ([a](https://stackoverflow.com/questions/1129894/why-cant-you-use-offsetof-on-non-pod-structures-in-c) [few](https://stackoverflow.com/questions/13180842/how-to-calculate-offset-of-a-class-member-at-compile-time) [examples](https://stackoverflow.com/questions/177885/looking-for-something-similar-to-offsetof-for-non-pod-types)). There is clearly a need in such functionality, and the lack of official support by the standard `offsetof` leads to attempts to work around the limitation, often involving undefined behavior and non-portable compiler-specific tricks.

# 3. Impact on the Standard

This proposal is a pure extension to the C++ language and standard library. Its intent is to define behavior that was previously not defined, in a way that most current implementations already work. No existing valid code is made invalid or changes its behavior.

# 4. Design Decisions

## 4.1. Trivially-copyable Types

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

## 4.2. Non-trivially-copyable Classes

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

The type `C` is no longer trivially-copyable, but is it no longer viable for inter-process communication? Is the mere presence of a user-defined copy constructor and assignment operator the limiting factor that prevents this? The author believes not, and indeed in the most widespread ABIs ([Itanium C++ ABI](https://mentorembedded.github.io/cxx-abi/abi.html), as well as Microsoft Windows x64 ABI) binary layout does not depend on the presence of the special member functions. The author believes that there is no practical benefit in leaving the opportunity to do otherwise. With this in mind, supporting this category of classes in `offsetof` is similar to trivially-copyable classes.

## 4.3. Classes with Virtual Functions and/or Virtual Base Classes

The most common implementation of virtual functions involves a virtual function table (vtable), a pointer to which is stored as a hidden data member in class objects. Like virtual functions, virtual base classes also typically introduce a hidden data member (vtordisp). This member is used to obtain the address of the virtual base class subobject at runtime. The size and position of these hidden members are constant, so they do not preclude `offsetof` from working as expected.

It is possible that other implementations of virtual functions or virtual base classes exist. However, the author is not aware of implementations that make non-static data member layout for a given class a runtime property that is not available at compile time. Such a design would compilcate ABI definition and likely have significant performance consequences with no apparent benefits. Therefore, the author considers such a design unlikely to be implemented and not worth allowing for, compared to the benefit from the improved support for `offsetof`.

Provided the above, it is possible to to calculate the offset of a data member at compile time given that the final type of the complete object is known. In this case the compiler has full knowledge of layout of non-static data members in the object and does not require runtime resolution of the address of the base class subobject. Fortunately, the way `offsetof` is defined in the [C standard](http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf) (7.19/3), to which C++ refers in [support.types.layout]/1, it is compatible with this precondition:

<blockquote><p>
The macros are [...]; and
<pre><code>
offsetof(<i>type</i>, <i>member-designator</i>)
</code></pre>
which expands to an integer constant expression that has type <tt>size_t</tt>, the value of
which is the offset in bytes, to the structure member (designated by <i>member-designator</i>),
from the beginning of its structure (designated by <i>type</i>). The type and member designator
shall be such that given
<pre><code>
static <i>type</i> t;
</code></pre>
then the expression <tt>&amp;(t.<i>member-designator</i>)</tt> evaluates to an address constant. (If the
specified member is a bit-field, the behavior is undefined.)
</p></blockquote>

The object `t` in this definition is the complete object that has the type that is specified as the first argument of `offsetof`.

## 4.3.1. Abstract Classes

Complete objects of abstract classes cannot be created, which puts them in conflict with the `offsetof` definition given in the C standard and quoted above. However, the object that is used in the definition is only given for the purpose of the definition itself; invoking `offsetof` does not result in creation of the object of class *type*. Therefore, this proposal does not exclude abstract classes from `offsetof` support.

## 4.4. Reference Data Members

The definition of `offsetof(type, member-designator)` in [support.types.layout]/1 refers to the C standard, and it only requires `&(t.member-designator)` to evaluate to an address constant (here, `t` is an object of class `type`). Since this proposal allows using `offsetof` with non-trivial types, `member-designator` can now identify a reference member. Taking the address of a reference member would result in the address of a referred object, which is not the intended effect of `offsetof`. For this reason, this proposal prohibits the use of references in a `member-designator`; the behavior is undefined if this requirement is violated. Note that this rule applies if references are used at any level of `member-designator`, if it identifies a nested member. For example:

```cpp
struct Bad
{
    int& n;
    A& a;
    int x;
};

offsetof(Bad, n);    // undefined behavior, Bad::n is a reference
offsetof(Bad, a.a);  // undefined behavior, Bad::a is a reference
offsetof(Bad, x);    // ok, returns offset of Bad::x
```

## 4.5. Object Storage and Data Member Layout

In order for `offsetof` to be able to operate and provide a useful result, certain requirements must be fulfilled:

 - most derived objects ([intro.object]/6) of a class compatible with `offsetof` must occupy a contiguous region of storage, and
 - offsets to non-static data members of such class must be constant and not depend on a particular most derived object of that class (this proposal refers to this property as *offset stability* or *stability of offsets*).

The first requirement allows to obtain the offset information and then apply it to an object and the second requirement guarantees that the information can be applied to any most derived object of that class.

Currently, the standard only guarantees contiguous storage for objects of trivially copyable or standard-layout types ([intro.object]/7). This proposal requires contiguous storage for objects of any type, except for objects that have virtual base class subobjects. Virtual base class subobjects may occupy storage bytes that are not immediately adjacent to the containing object, if that object is also a base class subobject. For example:

```cpp
struct X
{
    int a;
};

struct V : virtual public X
{
    int b;
};

struct Y : public V
{
    int c;
};

V v;
Y y;
```

Both `v` and `y` are required to occupy contiguous bytes of storage, but the subobject of `y` that represents the base class `V` may not be stored contiguously if the implementation chooses the following data layout:

```
-----
|*V*|
-----
| Y |
-----
|*X*|
-----
```

In this layout, the storage used by the base class `V` subobject is marked with asterisks (\*).

Note also that the requirement of contiguous storage does not mean that any implementation-specific data such as virtual function tables or virtual base displacement tables need to be placed in the object's storage. These kinds of data do not contribute to the object's value representation ([basic.types]/4) and therefore don't need to occupy the object storage.

The standard has no explicit provision about stability of offsets of non-static data members across different objects of a class. For trivially copyable classes the data member offsets are required to be stable, as discussed in section 4.1. For standard-layout classes the current definition of `offsetof` implies that members of such classes must have stable offsets. By extending `offsetof` to support other class types, this proposal requires that member offsets are stable for all classes.

# 5. Impact on Existing Implementations

The currently widespread compilers (GCC 7.2, Clang 4.0.1, MSVC 19.12.25831) all support `offsetof` for classes `A`, `B` and `C` described above, as well as classes with virtual functions (including pure virtual functions), although some of the compilers emit warnings, as currently required by N4713. This proposal makes all classes supported unconditionally, which will remove the need for a warning.

The tested compilers also have limited support for `offsetof` with classes with virtual base classes.

```cpp
struct D : virtual public A
{
    int c;
    char str[1024];
};

offsetof(D, a);       // (1)
offsetof(D, c);       // (2)
offsetof(D, str);     // (3)
offsetof(D, str[10]); // (4)
```

In the above example, all three tested compilers were able to compile all `offsetof` expressions, except (1), which is the only one that requests an offset of a member of a virtual base class. The updated compilers would have to be able to calculate the offset to members of virtual base classes in compile time.

Other than the case (1), all tested compilers appeared to return values that are aligned with this proposal (i.e. the returned values were equal to the offset to the requested member in a *complete* object of the specified type). Therefore, even programs that previously relied on implementation-specific behavior of `offsetof` are unlikely to be affected.

# 6. Proposed Wording

The proposed wording below is given relative to N4713. Inserted text is marked like <ins>this</ins>, removed text is marked like <del>this</del>.

## 6.1. Core Wording

Modify [intro.object]/7:

<blockquote>
<p>Unless it is a bit-field (12.2.4), a most derived object shall have a nonzero size and shall occupy one or more bytes of storage. Base class subobjects may have zero size. A<del>n</del><ins> most derived</ins> object <del>of trivially copyable or standard-layout type (6.7)</del><ins>or a base class subobject of nonzero size excluding any of its virtual base class (13.1) subobjects</ins> shall occupy contiguous bytes of storage.<ins> A virtual base class subobject may occupy a distinct non-adjacent contiguous region of storage from the rest of its containing base class subobject. Each such region of storage shall be within the enclosing contiguous region of storage occupied by the containing most derived object.</ins></p>
</blockquote>

## 6.2. Library Wording

Modify [support.types.layout]/1:

<blockquote>
<p>The macro <tt>offsetof</tt>(<i>type</i>, <i>member-designator</i>) has the same semantics as the corresponding macro in the C standard library header <tt>&lt;stddef.h&gt;</tt>, <del>but accepts a restricted set of <i>type</i> arguments in this International Standard. Use of the <tt>offsetof</tt> macro with a <i>type</i> other than a standard-layout class (Clause 12) is conditionally-supported</del><ins>with the following additions</ins>. The expression <tt>offsetof</tt>(<i>type</i>, <i>member-designator</i>) is never type-dependent (17.7.2.2) and it is value-dependent (17.7.2.3) if and only if <i>type</i> is dependent. The result of applying the <tt>offsetof</tt> macro to a static data member or a function member is undefined.<ins> Given the object <tt>t</tt> of type <i>type</i>, if <tt>t.<i>member-designator</i></tt> accesses or identifies a reference data member, the result of the <tt>offsetof</tt> macro is undefined.</ins> No operation invoked by the <tt>offsetof</tt> macro shall throw an exception and <tt>noexcept(offsetof(<i>type</i>, <i>member-designator</i>))</tt> shall be <tt>true</tt>.</p>
</blockquote>

# 7. Acknowledgements

 - Thanks to Walter E. Brown for the help with preparing and presenting the proposal.

# 8. References

 - P0545R0 proposal, Supporting <tt>offsetof</tt> for Stable-layout Classes ([http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0545r0.html](http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0545r0.html))
 - N4713 Working Draft, Standard for Programming Language C++ ([http://open-std.org/JTC1/SC22/WG21/docs/papers/2017/n4713.pdf](http://open-std.org/JTC1/SC22/WG21/docs/papers/2017/n4713.pdf))
 - N1570 Working Draft, Programming languages &dash; C ([http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf](http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf))
 - Itanium C++ ABI ([https://mentorembedded.github.io/cxx-abi/abi.html](https://mentorembedded.github.io/cxx-abi/abi.html))
