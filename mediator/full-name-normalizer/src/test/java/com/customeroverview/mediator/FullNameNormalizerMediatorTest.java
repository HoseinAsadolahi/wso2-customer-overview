package com.customeroverview.mediator;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class FullNameNormalizerMediatorTest {

    @Test
    void trimsAndCollapsesWhitespaceAndNormalizesCase() {
        assertEquals("Ali Rezaei", FullNameNormalizerMediator.normalize("   aLi    rEzAeI  "));
        assertEquals("Sara Mohammadi", FullNameNormalizerMediator.normalize("\tSARA\u00A0\u00A0mohammadi\n"));
    }

    @Test
    void normalizesArabicCharactersToPersian() {
        assertEquals("علی کریمی", FullNameNormalizerMediator.normalize("  علي   كريمي  "));
    }

    @Test
    void handlesNullAndBlankSafely() {
        assertEquals("", FullNameNormalizerMediator.normalize(null));
        assertEquals("", FullNameNormalizerMediator.normalize("    "));
    }
}
