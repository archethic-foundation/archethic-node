/* ---------------------------------------------
 common scripts
 --------------------------------------------- */

 ;(function () {

    "use strict"; // use strict to start


    /* ---------------------------------------------
     wow animation
     --------------------------------------------- */

    new WOW().init();

    if ($(window).width() <= 991){
        $(".wow").removeClass("wow");
    }


    /* ---------------------------------------------
     Smooth scrolling using jQuery easing
     --------------------------------------------- */

    $('a.js-scroll-trigger[href*="#"]:not([href="#"])').on('click', function() {
        if (location.pathname.replace(/^\//, '') == this.pathname.replace(/^\//, '') && location.hostname == this.hostname) {
            var target = $(this.hash);
            target = target.length ? target : $('[name=' + this.hash.slice(1) + ']');
            if (target.length) {
                target.css('paddingTop','50px');
                $('html, body').animate({
                    scrollTop: (target.offset().top)
                }, 1000);
                return false;
            }
        }
    });

    // Closes responsive menu when a scroll trigger link is clicked
    $('.js-scroll-trigger').on('click', function() {
        $('.navbar-collapse').collapse('hide');
    });

    $('.dropdown-item').on('click', function() {
        $('.dropdown-menu').removeClass('show');
    });

    // Activate scrollspy to add active class to navbar items on scroll
    $('body').scrollspy({
        target: '#mainNav'
    });


    /* ---------------------------------------------
     add sticky
     --------------------------------------------- */

    $(window).on('scroll', function () {
        var wSize = $(window).width();
        if (wSize > 767 && $(this).scrollTop() > 1) {
            $('.app-header').addClass("navbar-sticky");
        }
        else {
            $('.app-header').removeClass("navbar-sticky");
        }
    });


    /* ---------------------------------------------
     steps carousel
     --------------------------------------------- */

    $('.js_steps_carousel').owlCarousel({
        loop: true,
        margin: 0,
        autoplay: false,
        nav:false,
        //navText: ["<a><span></span></a>","<a><span></span></a>"],
        autoHeight:true,
        dots: true,
        dotsData: true,
        //animateOut: 'slideOutUp',
        //animateIn: 'slideInUp',
        responsive: {
            0: {
                items: 1
            },
            600: {
                items: 1
            },
            1000: {
                items: 1
            }
        }
    });

    /* ---------------------------------------------
     team carousel
     --------------------------------------------- */

    $('.js_team_member').owlCarousel({
        items: 4,
        loop: true,
        margin: 5,
        autoplay: false,
        nav:false,
        //navText: ["<a><span></span></a>","<a><span></span></a>"],
        autoHeight:true,
        dots: true,
        //animateOut: 'slideOutUp',
        //animateIn: 'slideInUp',
        responsive: {
            0: {items: 1, margin: 10},
            480: {items: 2, margin: 10, center: true},
            599: {items: 2,  margin: 10},
            768: {items: 5, margin: 10, center: true},
            1170: {items: 5, margin: 20, center: true}
        }
    });

    /* ---------------------------------------------
     advisory board carousel
     --------------------------------------------- */

    $('.js_advisory_board').owlCarousel({
        loop: true,
        margin: 0,
        autoplay: false,
        nav:false,
        //navText: ["<a><span></span></a>","<a><span></span></a>"],
        autoHeight:true,
        dots: true,
        dotsData: true,
        //animateOut: 'slideOutUp',
        //animateIn: 'slideInUp',
        responsive: {
            0: {
                items: 1
            },
            600: {
                items: 1
            },
            1000: {
                items: 1
            }
        }
    });

    /* ---------------------------------------------
     road map carousel
     --------------------------------------------- */

    $('.js_road_map').owlCarousel({
        items: 5,
        nav: true,
        dots: true,
        margin: 30,
        navText: ["<i class='fa fa-angle-left'></i>", "<i class='fa fa-angle-right'></i>"],
        // navText: ["<svg class='fas fa-angle-left'></svg>", "<svg class='fas fa-angle-right'></svg>"],
        responsive: {
            0: {items: 1},
            400: {items: 2, center: true},
            599: {items: 3},
            1024: {items: 4},
            1170: {items: 5}
        }
    });

    /*==============================================
     Countdown
     ===============================================*/

     $('#counting-date').countdown('2019/12/12').on('update.countdown', function(event) {
         var $this = $(this).html(event.strftime(''
         + '<div class="count-block"><h2>%D</h2> <span>Days</span></div>' + '<span class="colon">:</span>'
         + '<div class="count-block"><h2>%H</h2> <span>Hours</span> </div>' + '<span class="colon">:</span>'
         + '<div class="count-block"><h2>%M</h2> <span>Minutes</span> </div>' + '<span class="colon">:</span>'
         + '<div class="count-block"><h2>%S</h2> <span>Seconds</span></div>'));
     });

   

    

    /*==============================================
     magnific popup
     ===============================================*/

    $(".popup-youtube, .popup-vimeo, .popup-gmaps").magnificPopup({
        disableOn: 700,
        type: "iframe",
        mainClass: "mfp-fade",
        removalDelay: 160,
        preloader: false,
        fixedContentPos: false
    });

    var YP_List = {
        "fr": "assets/yellowpapers/UNIRIS-YellowPaper-Saison1-Reseau.pdf",
        "en": "assets/yellowpapers/UNIRIS-YellowPaper-Season1-Network.pdf",
    }

    console.log('ok')

    var end = new Date('2019/12/12')
    var today = new Date()
    var start = new Date('2019/09/16')
    var progress = Math.round(((today - start) / (end - start)) * 100)
    $('#progress-presale').css({ width: 40 * (progress / 100) + "%" })
    $('#progress-presale').attr('aria-valuenow', progress)

})(jQuery);

!function (e) {
    $("#particles-js").length > 0 && particlesJS("particles-js", {
        particles: {
            number: {
                value: 40,
                density: {enable: !0, value_area: 1000}
            },
            color: {value: "#fff"},
            shape: {
                type: "circle",
                opacity: .1,
                stroke: {width: 0, color: "#fff"},
                polygon: {nb_sides: 5}
            },
            opacity: {value: .3, random: !1, anim: {enable: !1, speed: 1, opacity_min: .12, sync: !1}},
            size: {value: 6, random: !0, anim: {enable: !1, speed: 40, size_min: .08, sync: !1}},
            line_linked: {enable: !0, distance: 150, color: "#fff", opacity: .3, width: 1.3},
            move: {
                enable: !0,
                speed: 5,
                direction: "none",
                random: !1,
                straight: !1,
                out_mode: "out",
                bounce: !1,
                attract: {enable: !1, rotateX: 500, rotateY: 1000}
            }
        },
        interactivity: {
            detect_on: "canvas",
            events: {onhover: {enable: !0, mode: "repulse"}, onclick: {enable: !0, mode: "push"}, resize: !0},
            modes: {
                grab: {distance: 400, line_linked: {opacity: 1}},
                bubble: {distance: 400, size: 40, duration: 2, opacity: 8, speed: 3},
                repulse: {distance: 200, duration: .4},
                push: {particles_nb: 4},
                remove: {particles_nb: 2}
            }
        },
        retina_detect: !0
    })
}(jQuery);

$("#contactForm").validator().on("submit", function (event) {
    if (event.isDefaultPrevented()) {
        // handle the invalid form...
        formError();
        submitMSG(false, "Did you fill in the form properly?");
    } else {
        // everything looks good!
        event.preventDefault();
        submitForm();
    }
});

function submitForm(){
    // Initiate Variables With Form Content
    var name = $("#name").val();
    var email = $("#email").val();
    var msg_subject = $("#msg_subject").val();
    var message = $("#message").val();


    $.ajax({
        type: "POST",
        url: "https://uniris.io/assets/php/form-process.php",
        data: "name=" + name + "&email=" + email + "&msg_subject=" + msg_subject + "&message=" + message,
        success : function(text){
            if (text == "success"){
                formSuccess();
            } else {
                formError();
                submitMSG(false,text);
            }
        }
    });
}

function formSuccess(){
    $("#contactForm")[0].reset();
    submitMSG(true, "Message Submitted!")
}

function formError(){
    //$("#contactForm").removeClass().addClass('shake animated-').one('webkitAnimationEnd mozAnimationEnd MSAnimationEnd oanimationend animationend', function(){
    //    $(this).removeClass();
    //});
}

function submitMSG(valid, msg){
    if(valid){
        var msgClasses = "h5 text-center tada- animated- text-success";
    } else {
        var msgClasses = "h5 text-center text-danger";
    }
    $("#msgSubmit").removeClass().addClass(msgClasses).text(msg);
}

$(window).scroll(function() {
    if ($(this).scrollTop() > 0) {
      $('.transaction_info').fadeOut();
    } else {
      $('.transaction_info').fadeIn();
    }
  });