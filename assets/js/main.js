// ===== MAIN JAVASCRIPT FOR PERSONAL WEBSITE =====

// DOM Elements
const navbar = document.getElementById('navbar');
const navToggle = document.getElementById('nav-toggle');
const navMenu = document.getElementById('nav-menu');
const navLinks = document.querySelectorAll('.nav-link');
const themeToggle = document.getElementById('theme-toggle');
const scrollTopBtn = document.getElementById('scroll-top');
const typewriterElement = document.querySelector('.typewriter');

// Configuration
const CONFIG = {
    typewriter: {
        texts: [
            'AI Solution Architect',
            'Generative AI Specialist',
            'Demand Forecasting Expert', 
            'Enterprise AI Strategist',
            'KENDI Framework Developer'
        ],
        typeSpeed: 100,
        deleteSpeed: 50,
        pauseTime: 2000
    },
    scroll: {
        navbarScrollThreshold: 100,
        scrollTopThreshold: 300
    },
    animation: {
        debounceDelay: 100
    }
};

// ===== UTILITY FUNCTIONS =====

// Debounce function for performance optimization
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// Throttle function for scroll events
function throttle(func, limit) {
    let inThrottle;
    return function() {
        const args = arguments;
        const context = this;
        if (!inThrottle) {
            func.apply(context, args);
            inThrottle = true;
            setTimeout(() => inThrottle = false, limit);
        }
    };
}

// Check if element is in viewport
function isInViewport(element, threshold = 0.1) {
    const rect = element.getBoundingClientRect();
    const windowHeight = window.innerHeight || document.documentElement.clientHeight;
    const windowWidth = window.innerWidth || document.documentElement.clientWidth;
    
    return (
        rect.top <= windowHeight * (1 - threshold) &&
        rect.bottom >= windowHeight * threshold &&
        rect.left <= windowWidth * (1 - threshold) &&
        rect.right >= windowWidth * threshold
    );
}

// Smooth scroll to element
function smoothScrollTo(target) {
    const targetElement = document.querySelector(target);
    if (targetElement) {
        const headerOffset = 80;
        const elementPosition = targetElement.getBoundingClientRect().top;
        const offsetPosition = elementPosition + window.pageYOffset - headerOffset;

        window.scrollTo({
            top: offsetPosition,
            behavior: 'smooth'
        });
    }
}

// ===== TYPEWRITER EFFECT =====
class TypewriterEffect {
    constructor(element, texts, options = {}) {
        this.element = element;
        this.texts = texts;
        this.typeSpeed = options.typeSpeed || 100;
        this.deleteSpeed = options.deleteSpeed || 50;
        this.pauseTime = options.pauseTime || 2000;
        this.textIndex = 0;
        this.charIndex = 0;
        this.isDeleting = false;
        this.isTyping = false;
        
        this.init();
    }
    
    init() {
        if (this.element) {
            this.type();
        }
    }
    
    type() {
        const currentText = this.texts[this.textIndex];
        
        if (this.isDeleting) {
            this.element.textContent = currentText.substring(0, this.charIndex - 1);
            this.charIndex--;
        } else {
            this.element.textContent = currentText.substring(0, this.charIndex + 1);
            this.charIndex++;
        }
        
        let typeSpeed = this.isDeleting ? this.deleteSpeed : this.typeSpeed;
        
        if (!this.isDeleting && this.charIndex === currentText.length) {
            // Pause at end of text
            typeSpeed = this.pauseTime;
            this.isDeleting = true;
        } else if (this.isDeleting && this.charIndex === 0) {
            this.isDeleting = false;
            this.textIndex = (this.textIndex + 1) % this.texts.length;
        }
        
        setTimeout(() => this.type(), typeSpeed);
    }
}

// ===== NAVIGATION FUNCTIONALITY =====
class Navigation {
    constructor() {
        this.init();
    }
    
    init() {
        this.setupEventListeners();
        this.setupActiveNavigation();
    }
    
    setupEventListeners() {
        // Mobile menu toggle
        if (navToggle && navMenu) {
            navToggle.addEventListener('click', () => {
                navMenu.classList.toggle('active');
                navToggle.classList.toggle('active');
                
                // Prevent body scroll when menu is open
                document.body.style.overflow = navMenu.classList.contains('active') ? 'hidden' : '';
            });
        }
        
        // Close mobile menu when clicking on a link
        navLinks.forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                const target = link.getAttribute('href');
                
                // Close mobile menu
                navMenu.classList.remove('active');
                navToggle.classList.remove('active');
                document.body.style.overflow = '';
                
                // Smooth scroll to target
                smoothScrollTo(target);
            });
        });
        
        // Close mobile menu when clicking outside
        document.addEventListener('click', (e) => {
            if (!navMenu.contains(e.target) && !navToggle.contains(e.target)) {
                navMenu.classList.remove('active');
                navToggle.classList.remove('active');
                document.body.style.overflow = '';
            }
        });
    }
    
    setupActiveNavigation() {
        const sections = document.querySelectorAll('section[id]');
        
        const updateActiveNavigation = throttle(() => {
            let currentSection = '';
            
            sections.forEach(section => {
                const sectionTop = section.getBoundingClientRect().top;
                const sectionHeight = section.offsetHeight;
                
                if (sectionTop <= 100 && sectionTop + sectionHeight > 100) {
                    currentSection = section.getAttribute('id');
                }
            });
            
            navLinks.forEach(link => {
                link.classList.remove('active');
                if (link.getAttribute('href') === `#${currentSection}`) {
                    link.classList.add('active');
                }
            });
        }, 100);
        
        window.addEventListener('scroll', updateActiveNavigation);
        updateActiveNavigation(); // Initial call
    }
}

// ===== SCROLL EFFECTS =====
class ScrollEffects {
    constructor() {
        this.init();
    }
    
    init() {
        this.setupScrollEffects();
        this.setupScrollToTop();
    }
    
    setupScrollEffects() {
        const handleScroll = throttle(() => {
            const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
            
            // Navbar effects
            if (navbar) {
                if (scrollTop > CONFIG.scroll.navbarScrollThreshold) {
                    navbar.classList.add('scrolled');
                } else {
                    navbar.classList.remove('scrolled');
                }
            }
            
            // Scroll to top button
            if (scrollTopBtn) {
                if (scrollTop > CONFIG.scroll.scrollTopThreshold) {
                    scrollTopBtn.classList.add('visible');
                } else {
                    scrollTopBtn.classList.remove('visible');
                }
            }
            
            // Parallax effect for hero section
            const hero = document.querySelector('.hero');
            if (hero && scrollTop < window.innerHeight) {
                const parallaxSpeed = 0.5;
                hero.style.transform = `translateY(${scrollTop * parallaxSpeed}px)`;
            }
        }, 16); // ~60fps
        
        window.addEventListener('scroll', handleScroll);
        handleScroll(); // Initial call
    }
    
    setupScrollToTop() {
        if (scrollTopBtn) {
            scrollTopBtn.addEventListener('click', () => {
                window.scrollTo({
                    top: 0,
                    behavior: 'smooth'
                });
            });
        }
    }
}

// ===== THEME TOGGLE =====
class ThemeManager {
    constructor() {
        this.currentTheme = localStorage.getItem('theme') || 'dark';
        this.init();
    }
    
    init() {
        this.setTheme(this.currentTheme);
        this.setupEventListeners();
    }
    
    setupEventListeners() {
        if (themeToggle) {
            themeToggle.addEventListener('click', () => {
                this.toggleTheme();
            });
        }
    }
    
    setTheme(theme) {
        document.documentElement.setAttribute('data-theme', theme);
        localStorage.setItem('theme', theme);
        this.currentTheme = theme;
        
        // Update theme toggle icon
        if (themeToggle) {
            const icon = themeToggle.querySelector('i');
            if (icon) {
                icon.className = theme === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
            }
        }
    }
    
    toggleTheme() {
        const newTheme = this.currentTheme === 'dark' ? 'light' : 'dark';
        this.setTheme(newTheme);
    }
}

// ===== ANIMATIONS AND INTERACTIONS =====
class AnimationManager {
    constructor() {
        this.init();
    }
    
    init() {
        this.setupCounterAnimations();
        this.setupSkillHoverEffects();
        this.setupProjectCardEffects();
        this.setupFormAnimations();
    }
    
    setupCounterAnimations() {
        const counters = document.querySelectorAll('.stat-number');
        
        const animateCounter = (counter) => {
            const target = parseInt(counter.textContent.replace(/\D/g, ''));
            const duration = 2000;
            const step = target / (duration / 16);
            let current = 0;
            
            const updateCounter = () => {
                current += step;
                if (current < target) {
                    counter.textContent = Math.floor(current) + '+';
                    requestAnimationFrame(updateCounter);
                } else {
                    counter.textContent = target + '+';
                }
            };
            
            updateCounter();
        };
        
        // Intersection Observer for counter animation
        const counterObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    const counter = entry.target;
                    if (!counter.classList.contains('animated')) {
                        counter.classList.add('animated');
                        animateCounter(counter);
                    }
                }
            });
        }, { threshold: 0.7 });
        
        counters.forEach(counter => {
            counterObserver.observe(counter);
        });
    }
    
    setupSkillHoverEffects() {
        const skillItems = document.querySelectorAll('.skill-item');
        
        skillItems.forEach(item => {
            item.addEventListener('mouseenter', () => {
                item.style.transform = 'scale(1.05) translateY(-2px)';
            });
            
            item.addEventListener('mouseleave', () => {
                item.style.transform = 'scale(1) translateY(0)';
            });
        });
    }
    
    setupProjectCardEffects() {
        const projectCards = document.querySelectorAll('.project-card');
        
        projectCards.forEach(card => {
            card.addEventListener('mouseenter', () => {
                card.style.transform = 'translateY(-10px) scale(1.02)';
            });
            
            card.addEventListener('mouseleave', () => {
                card.style.transform = 'translateY(0) scale(1)';
            });
        });
    }
    
    setupFormAnimations() {
        // Add floating label effect for any form inputs
        const formInputs = document.querySelectorAll('input, textarea');
        
        formInputs.forEach(input => {
            input.addEventListener('focus', () => {
                input.parentElement.classList.add('focused');
            });
            
            input.addEventListener('blur', () => {
                if (!input.value) {
                    input.parentElement.classList.remove('focused');
                }
            });
        });
    }
}

// ===== PERFORMANCE OPTIMIZATIONS =====
class PerformanceManager {
    constructor() {
        this.init();
    }
    
    init() {
        this.setupLazyLoading();
        this.preloadCriticalResources();
        this.optimizeAnimations();
    }
    
    setupLazyLoading() {
        const images = document.querySelectorAll('img[data-src]');
        
        const imageObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    const img = entry.target;
                    img.src = img.dataset.src;
                    img.classList.add('loaded');
                    imageObserver.unobserve(img);
                }
            });
        });
        
        images.forEach(img => imageObserver.observe(img));
    }
    
    preloadCriticalResources() {
        // Preload hero image and other critical assets
        const criticalImages = [
            'assets/img/profile.jpg',
            'assets/img/project-kendi.jpg',
            'assets/img/project-automation.jpg',
            'assets/img/project-copilot.jpg'
        ];
        
        criticalImages.forEach(src => {
            const link = document.createElement('link');
            link.rel = 'preload';
            link.as = 'image';
            link.href = src;
            document.head.appendChild(link);
        });
    }
    
    optimizeAnimations() {
        // Reduce animations for users who prefer reduced motion
        if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
            document.documentElement.style.setProperty('--transition-fast', '0.01ms');
            document.documentElement.style.setProperty('--transition-normal', '0.01ms');
            document.documentElement.style.setProperty('--transition-slow', '0.01ms');
        }
    }
}

// ===== CONTACT FORM FUNCTIONALITY =====
class ContactManager {
    constructor() {
        this.init();
    }
    
    init() {
        this.setupContactLinks();
        this.setupDownloadTracking();
    }
    
    setupContactLinks() {
        // Add click tracking for contact links
        const contactLinks = document.querySelectorAll('a[href^="mailto:"], a[href^="tel:"]');
        
        contactLinks.forEach(link => {
            link.addEventListener('click', (e) => {
                // Track contact interactions
                const linkType = link.href.startsWith('mailto:') ? 'email' : 'phone';
                console.log(`Contact interaction: ${linkType}`);
                
                // You can add analytics tracking here
                if (typeof gtag !== 'undefined') {
                    gtag('event', 'contact_click', {
                        'contact_method': linkType
                    });
                }
            });
        });
    }
    
    setupDownloadTracking() {
        // Track resume downloads
        const downloadLinks = document.querySelectorAll('a[download]');
        
        downloadLinks.forEach(link => {
            link.addEventListener('click', (e) => {
                console.log('Resume download initiated');
                
                // You can add analytics tracking here
                if (typeof gtag !== 'undefined') {
                    gtag('event', 'file_download', {
                        'file_name': 'resume.pdf'
                    });
                }
            });
        });
    }
}

// ===== EASTER EGGS AND ENHANCEMENTS =====
class EasterEggs {
    constructor() {
        this.konamiCode = ['ArrowUp', 'ArrowUp', 'ArrowDown', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'ArrowLeft', 'ArrowRight', 'KeyB', 'KeyA'];
        this.userInput = [];
        this.init();
    }
    
    init() {
        this.setupKonamiCode();
        this.setupConsoleMessage();
    }
    
    setupKonamiCode() {
        document.addEventListener('keydown', (e) => {
            this.userInput.push(e.code);
            this.userInput = this.userInput.slice(-this.konamiCode.length);
            
            if (this.userInput.join(',') === this.konamiCode.join(',')) {
                this.activateEasterEgg();
            }
        });
    }
    
    activateEasterEgg() {
        // Add fun animation or effect
        document.body.style.animation = 'rainbow 1s infinite';
        
        // Show message
        const message = document.createElement('div');
        message.innerHTML = '🎉 You found the secret! Automation magic activated! 🎉';
        message.style.cssText = `
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: var(--gradient-primary);
            color: white;
            padding: 2rem;
            border-radius: 1rem;
            z-index: 10000;
            font-size: 1.2rem;
            text-align: center;
            box-shadow: var(--shadow-xl);
        `;
        
        document.body.appendChild(message);
        
        setTimeout(() => {
            document.body.removeChild(message);
            document.body.style.animation = '';
        }, 3000);
    }
    
    setupConsoleMessage() {
        console.log(`
        🚀 Welcome to Marvin's Portfolio!
        
        Interested in the code? Check out the GitHub repository!
        
        Built with:
        - Vanilla JavaScript (no frameworks needed!)
        - Modern CSS with custom properties
        - Semantic HTML5
        - Responsive design principles
        - Performance optimizations
        - Accessibility best practices
        
        Want to chat about AI solutions, demand forecasting, or GenAI implementations?
        Feel free to reach out! 
        `);
    }
}

// ===== INITIALIZATION =====
class Website {
    constructor() {
        this.init();
    }
    
    async init() {
        // Wait for DOM to be fully loaded
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => this.initializeComponents());
        } else {
            this.initializeComponents();
        }
    }
    
    initializeComponents() {
        try {
            // Initialize AOS (Animate On Scroll)
            if (typeof AOS !== 'undefined') {
                AOS.init({
                    duration: 1000,
                    easing: 'ease-out-cubic',
                    once: true,
                    offset: 100
                });
            }
            
            // Initialize typewriter effect
            if (typewriterElement) {
                new TypewriterEffect(
                    typewriterElement,
                    CONFIG.typewriter.texts,
                    CONFIG.typewriter
                );
            }
            
            // Initialize all components
            new Navigation();
            new ScrollEffects();
            new ThemeManager();
            new AnimationManager();
            new PerformanceManager();
            new ContactManager();
            new EasterEggs();
            
            // Setup error handling
            this.setupErrorHandling();
            
            console.log('🎉 Website initialized successfully!');
            
        } catch (error) {
            console.error('Error initializing website:', error);
            this.handleInitializationError(error);
        }
    }
    
    setupErrorHandling() {
        window.addEventListener('error', (event) => {
            console.error('Runtime error:', event.error);
        });
        
        window.addEventListener('unhandledrejection', (event) => {
            console.error('Unhandled promise rejection:', event.reason);
        });
    }
    
    handleInitializationError(error) {
        // Graceful degradation - ensure basic functionality works
        console.warn('Falling back to basic functionality due to initialization error');
        
        // At minimum, ensure navigation works
        document.querySelectorAll('a[href^="#"]').forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                const target = document.querySelector(link.getAttribute('href'));
                if (target) {
                    target.scrollIntoView({ behavior: 'smooth' });
                }
            });
        });
    }
}

// ===== START THE WEBSITE =====
new Website();

// ===== EXPORT FOR TESTING (if in module environment) =====
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        TypewriterEffect,
        Navigation,
        ScrollEffects,
        ThemeManager,
        AnimationManager,
        PerformanceManager,
        ContactManager,
        EasterEggs,
        Website
    };
}