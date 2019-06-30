<table>
<tr><td>Title:</td><td>Rename <tt>index_type</tt> to <tt>size_type</tt> in <tt>std::span</tt></td></tr>
<tr><td>Document number:</td><td>D0000R0</td></tr>
<tr><td>Date:</td><td>2019-30-06</td></tr>
<tr><td>Project:</td><td>ISO JTC1/SC22/WG21: Programming Language C++</td></tr>
<tr><td>Audience:</td><td>LWG</td></tr>
<tr><td>Reply-to:</td><td>Andrey Semashev &lt;andrey.semashev at gmail dot com&gt;</td></tr>
</table>

# 1. Proposal

This proposal modifies the `std::span` class template to be more compatible with other range types in the standard library and other widespread libraries, like Boost and Qt. Specifically, this document proposes to rename the `index_type` member type of `span` to `size_type`. The type is still an alias to `size_t` and has the same usage as before.

# 2. Rationale

The convention, where a range type, such as container, string or view, has a member type named `size_type` that is used to convey the number of elements and index into the sequence, is long established and widely used throughout the standard library and beyond. All standard containers and even container adaptors, strings (including `string_view`), `array`, `initializer_list`, containers and ranges in Boost and Qt libraries &mdash; all follow this convention, except `span`. The convention has been followed for many years, and there is arguably a lot of existing code relying on it. There is no reason for `span` to not follow it as well, as it will make it more compatible with generic code relying on the `size_type` member type.

# 3. Impact on the Standard

This proposal modifies a new component of the standard library, which has not been published in a final specification yet.

# 4. Impact on Existing Implementations

According to [cppreference.com](https://en.cppreference.com/w/cpp/compiler_support), the only major standard library that implements `span` is Clang libc++, starting with version 7. That implementation has evolved over time, and currently (as of 2019-06-30) defines `index_type` member type as an alias for `size_t`. That implementation will need to be changed to define `size_type`, which is trivial and can be made in a backward compatible way by also keeping `index_type`, should libc++ maintainers choose so.

# 5. Proposed Wording

The proposed wording below is given relative to [N4820](http://open-std.org/JTC1/SC22/WG21/docs/papers/2019/n4820.pdf). Inserted text is marked like <ins>this</ins>, removed text is marked like <del>this</del>.

Modify [span.overview]/2:

<blockquote>
<p>All member functions of span have constant time complexity.</p>
<p><code><pre>namespace std {
  template&lt;class ElementType, size_t Extent = dynamic_extent&gt;
  class span {
  public:
    // constants and types
    using element_type = ElementType;
    using value_type = remove_cv_t&lt;ElementType&gt;;
    using <del>index_type</del><ins>size_type</ins> = size_t;
    using difference_type = ptrdiff_t;
    using pointer = element_type*;
    using const_pointer = const element_type*;
    using reference = element_type&;
    using const_reference = const element_type&;
    using iterator = <i>implementation-defined</i>; // see 22.7.3.6
    using const_iterator = <i>implementation-defined</i>;
    using reverse_iterator = std::reverse_iterator&lt;iterator&gt;;
    using const_reverse_iterator = std::reverse_iterator&lt;const_iterator&gt;;
    static constexpr <del>index_type</del><ins>size_type</ins> extent = Extent;

    // 22.7.3.2, constructors, copy, and assignment
    constexpr span() noexcept;
    constexpr span(pointer ptr, <del>index_type</del><ins>size_type</ins> count);
    constexpr span(pointer first, pointer last);
    template&lt;size_t N&gt;
    constexpr span(element_type (&amp;arr)[N]) noexcept;
    template&lt;size_t N&gt;
    constexpr span(array&lt;value_type, N&gt;&amp; arr) noexcept;
    template&lt;size_t N&gt;
    constexpr span(const array&lt;value_type, N&gt;&amp; arr) noexcept;
    template&lt;class Container&gt;
    constexpr span(Container&amp; cont);
    template&lt;class Container&gt;
    constexpr span(const Container&amp; cont);
    constexpr span(const span&amp; other) noexcept = default;
    template&lt;class OtherElementType, size_t OtherExtent&gt;
    constexpr span(const span&lt;OtherElementType, OtherExtent&gt;&amp; s) noexcept;

    ~span() noexcept = default;

    constexpr span& operator=(const span&amp; other) noexcept = default;

    // 22.7.3.3, subviews
    template&lt;size_t Count&gt;
    constexpr span&lt;element_type, Count&gt; first() const;
    template&lt;size_t Count&gt;
    constexpr span&lt;element_type, Count&gt; last() const;
    template&lt;size_t Offset, size_t Count = dynamic_extent&gt;
    constexpr span&lt;element_type, <i>see below</i> &gt; subspan() const;

    constexpr span&lt;element_type, dynamic_extent&gt; first(<del>index_type</del><ins>size_type</ins> count) const;
    constexpr span&lt;element_type, dynamic_extent&gt; last(<del>index_type</del><ins>size_type</ins> count) const;
    constexpr span&lt;element_type, dynamic_extent&gt; subspan(
      <del>index_type</del><ins>size_type</ins> offset, <del>index_type</del><ins>size_type</ins> count = dynamic_extent) const;

    // 22.7.3.4, observers
    constexpr <del>index_type</del><ins>size_type</ins> size() const noexcept;
    constexpr <del>index_type</del><ins>size_type</ins> size_bytes() const noexcept;
    [[nodiscard]] constexpr bool empty() const noexcept;

    // 22.7.3.5, element access
    constexpr reference operator[](<del>index_type</del><ins>size_type</ins> idx) const;
    constexpr reference front() const;
    constexpr reference back() const;
    constexpr pointer data() const noexcept;

    // 22.7.3.6, iterator support
    constexpr iterator begin() const noexcept;
    constexpr iterator end() const noexcept;
    constexpr const_iterator cbegin() const noexcept;
    constexpr const_iterator cend() const noexcept;
    constexpr reverse_iterator rbegin() const noexcept;
    constexpr reverse_iterator rend() const noexcept;
    constexpr const_reverse_iterator crbegin() const noexcept;
    constexpr const_reverse_iterator crend() const noexcept;

    friend constexpr iterator begin(span s) noexcept { return s.begin(); }
    friend constexpr iterator end(span s) noexcept { return s.end(); }

  private:
    pointer data_; // exposition only
    <del>index_type</del><ins>size_type</ins> size_; // exposition only
  };

  template&lt;class T, size_t N&gt;
  span(T (&amp;)[N]) -&gt; span&lt;T, N&gt;;
  template&lt;class T, size_t N&gt;
  span(array&lt;T, N&gt;&amp;) -&gt; span&lt;T, N&gt;;
  template&lt;class T, size_t N&gt;
  span(const array&lt;T, N&gt;&amp;) -&gt; span&lt;const T, N&gt;;
  template&lt;class Container&gt;
  span(Container&amp;) -&gt; span&lt;typename Container::value_type&gt;;
  template&lt;class Container&gt;
  span(const Container&amp;) -&gt; span&lt;const typename Container::value_type&gt;;
}</pre></code></p>
</blockquote>

Modify constructor descriptions in [span.cons] accordingly:

<blockquote>
<tt>constexpr span(pointer ptr, <del>index_type</del><ins>size_type</ins> count);</tt>
</blockquote>

Modify member descriptions in [span.sub] accordingly:

<blockquote>
<tt>constexpr span&lt;element_type, dynamic_extent&gt; first(<del>index_type</del><ins>size_type</ins> count) const;</tt>
</blockquote>

<blockquote>
<tt>constexpr span&lt;element_type, dynamic_extent&gt; last(<del>index_type</del><ins>size_type</ins> count) const;</tt>
</blockquote>

<blockquote>
<tt>constexpr span&lt;element_type, dynamic_extent&gt; subspan(<del>index_type</del><ins>size_type</ins> offset, <del>index_type</del><ins>size_type</ins> count = dynamic_extent) const;</tt>
</blockquote>

Modify observer descriptions in [span.obs] accordingly:

<blockquote>
<tt>constexpr <del>index_type</del><ins>size_type</ins> size() const noexcept;</tt>
</blockquote>

<blockquote>
<tt>constexpr <del>index_type</del><ins>size_type</ins> size_bytes() const noexcept;</tt>
</blockquote>

Modify element access descriptions in [span.elem] accordingly:

<blockquote>
<tt>constexpr reference operator[](<del>index_type</del><ins>size_type</ins> idx) const;</tt>
</blockquote>

# 6. References

 - N4820 Working Draft, Standard for Programming Language C++ ([http://open-std.org/JTC1/SC22/WG21/docs/papers/2019/n4820.pdf](http://open-std.org/JTC1/SC22/WG21/docs/papers/2019/n4820.pdf))
